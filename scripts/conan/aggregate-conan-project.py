#
# Copyright 2026 metaeffekt GmbH.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
import concurrent.futures
import datetime
import hashlib
import io
import json
import multiprocessing
import os
import shutil
import sys
import tarfile
from time import sleep, strftime
from typing import Dict

"""
General usage:
This script ingests jsons output by a conan install command (with source download enabled!) and does its best to output
ready-to-use compliance artifacts including as much info about used sources as possible.
Due to how conan works, we can't guarantee that the package did not use any system libraries while building, but
we CAN read from its cache the sources the package itself references and used (given good enough conanfiles).

Suitable commands for complete-enough output may look like this:
conan install \
    -c tools.build:download_source=True \
    --requires=ros-kilted/2026.06.17 \
    --profile=ros-conan/profiles/ros \
    -o ros-kilted/*:variant=desktop \
    --build=missing \
    -f json --out-file conan_install_out.json
... or this:
conan install \
    -c tools.build:download_source=True \
    --profile=path-to-my-build-profile\
    --build=missing\
    -f json --out-file conan_install_out.json\
    .
... or simply this:
conan install \
    -c tools.build:download_source=True \
    --requires=my-package-goes-here/0.123.0 \
    --build=missing \
    -f json --out-file conan_install_out.json
... where conan_install_out is what this script will use for processing.
Note we require the full filesystem state of the build, so this script needs to

Troubleshooting tips:
    - if most or all sources are missing, check that conan install ran with
        source download (`-c tools.build:download_source=True`).
    - if sources and binaries or a buncha stuff in general is missing, check
        that the conan install and this python script are running on the same
        file system; the conan cache must be properly populated.
"""

global_exception_info = None


class RepackageTaskDescription:
    """
    After realizing that nodes are a bit messy to work with, node data is consolidated into a separate object.
    This object represents everything a thread needs while repackaging.
    """

    def __init__(self, node_identifier: str, ref: str = None, graph_nodes: set = set(), recipe_folder: str = None,
                 source_folder: str = None, package_folder: str = None, name: str = None, version: str = None,
                 user: str = None, channel: str = None, rrev: str = None, package_id: str = None, prev: str = None):
        self.__node_identifier = node_identifier
        self.ref = ref
        self.name = name
        self.version = version
        self.user = user
        self.channel = channel
        self.rrev = rrev
        self.package_id = package_id
        self.prev = prev
        
        if graph_nodes is None:
            printerr("Refusing to construct task with None set.")
            raise ValueError("Expecting valid set instance for graph_nodes.")
        self.graph_nodes = graph_nodes
        self.recipe_folder = recipe_folder
        self.source_folder = source_folder
        self.package_folder = package_folder

    @classmethod
    def new_with_identifiers_from_graph_node(cls, graph_node: dict):
        return cls(get_package_identifier_from_graph_node(graph_node), name=graph_node["name"],
                   version=graph_node["version"], user=graph_node["user"], channel=graph_node["channel"],
                   rrev=graph_node["rrev"], package_id=graph_node["package_id"], prev=graph_node["prev"])

    @property
    def node_identifier(self):
        return self.__node_identifier

    def do_new_value_check(self, old_folder: str, new_folder: str, folder_type_str: str):
        if new_folder and old_folder != new_folder:
            printerr(
                f"Nodes of node_identifier [{self.node_identifier}] disagree on recipe_folder:\n"
                f"  have: [{old_folder}]\n"
                f"  saw : [{new_folder}].")
            raise RuntimeError(f"Nodes for [{self.node_identifier}]'s task disagree on {folder_type_str}.")

    def set_or_check_recipe_folder(self, new_recipe_folder: str):
        # update only if current is unset
        self.recipe_folder = self.recipe_folder or new_recipe_folder
        self.do_new_value_check(self.recipe_folder, new_recipe_folder, "recipe_folder")

    def set_or_check_source_folder(self, new_source_folder: str):
        # update only if current is unset
        self.source_folder = self.source_folder or new_source_folder
        self.do_new_value_check(self.source_folder, new_source_folder, "source_folder")

    def set_or_check_package_folder(self, new_package_folder: str):
        # update only if current is unset
        self.package_folder = self.package_folder or new_package_folder
        self.do_new_value_check(self.package_folder, new_package_folder, "package_folder")

    def set_or_check_ref(self, new_ref: str):
        # update only if current is unset
        self.ref = self.ref or new_ref
        self.do_new_value_check(self.ref, new_ref, "ref")

    def __repr__(self):

        return str(vars(self))

def printerr(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def print_usage_and_exit():
    printerr("Usage: scriptname.py [conan graph json filename] [output dir for (re)package tars]")
    printerr(" - where the json is output from conan install.")
    printerr(" - conan install must have run completely and successfully;")
    printerr("   needed for active and complete build directories and such.")
    exit(1)


def read_json(input_json_filepath: str) -> dict:
    with open(input_json_filepath, mode="rt", encoding="utf-8") as f:
        json_file_content = f.read()

    return json.loads(json_file_content)


def strict_reproducible_filter(tarinfo: tarfile.TarInfo) -> tarfile.TarInfo:
    """
    Tries to remove some unnecessary metadata from the tar file headers.

    WARNING: This filter is a partly vibe-coded copy-paste job, partly completed and fixed properly.
    Point is to make output tar metadata less noisy with stuff
    carried over from the build system.
    """
    # clear some excess metadata
    tarinfo.uid = tarinfo.gid = 0
    tarinfo.uname = tarinfo.gname = ""
    tarinfo.mtime = 0

    # some permission defaults
    if tarinfo.isdir():
        tarinfo.mode = 0o700
    else:
        # notably clears executable bits on files
        tarinfo.mode = 0o600

    return tarinfo


# little hack that eases addition of text files
def add_text_file(tar: tarfile.TarFile, name_in_tar: str, text: str):
    b = text.encode("utf-8")
    tarinfo = tarfile.TarInfo(name=name_in_tar)
    tarinfo.size = len(b)

    tar.addfile(tarinfo, fileobj=io.BytesIO(b))


def dump_node_to_json(graph_node: dict) -> str:
    return json.dumps(graph_node, sort_keys=True, separators=(',', ':'))

def get_dedup_node(graph_node: dict) -> str:
    graph_node = dict(graph_node)
    graph_node.pop("id", None)
    graph_node.pop("dependencies", None)
    return graph_node

def get_node_hash(graph_node: dict) -> str:
    # note we hash raw output from dump function, without additional newlines
    return hashlib.sha256(dump_node_to_json(graph_node).encode("utf-8")).hexdigest()


def get_outdir_slice_1(task: RepackageTaskDescription):
    return (task.name or "") + "@" + (task.version or "")


def get_outdir_slice_2(task: RepackageTaskDescription):
    return (task.rrev or "") + "@" + (task.package_id or "") + "@" + (task.prev or "")


def dump_to_tar(task: RepackageTaskDescription, output_dir_for_repackaged: str) -> None:
    """
    Deduplicate nodes before running dump; output is named by prev.
    :param task: task object that represents what we're supposed to put into the (re)package
    :param output_dir_for_repackaged: where repackaged files will be put inside of
    """

    node_identifier = task.node_identifier
    print(f"processing node_identifier [{node_identifier}].")

    recipe_folder = task.recipe_folder
    source_folder = task.source_folder
    package_folder = task.package_folder

    # build identifier for sub-packages
    dir_slice_1 = output_dir_for_repackaged + "/" + get_outdir_slice_1(task)
    dir_path = dir_slice_1 + "/" + get_outdir_slice_2(task)

    # check to not accidentally overwrite existing stuff on a best-effort basis
    try:
        try:
            os.mkdir(dir_slice_1)
        except FileExistsError:
            pass
        # NOTE: if there are multiple tasks with the same rrev and unspecified package_id and prev, we'd crash here.
        os.mkdir(dir_path)
        os.mkdir(dir_path + "/graph_nodes")
    except FileExistsError as e:
        printerr(f"File {dir_path} already existed while processing task [{task.node_identifier}].")
        raise e

    for graph_node in task.graph_nodes:
        with open(dir_path + "/graph_nodes/" + f"{get_node_hash(graph_node)}.json", mode="w",
                  encoding="utf-8") as graph_node_file:
            graph_node_file.write(dump_node_to_json(graph_node))
            graph_node_file.write("\n")
    if task.ref == "conanfile":
        print("Skipping folders for ref 'conanfile'; usually empty. Its real identity should be part of the graph.")
        return
    elif not recipe_folder:
        raise RuntimeError("Should never be empty unless ref is conanfile")


    # output recipe part
    with tarfile.open(dir_path + "/recipe.tar", mode="x:") as tar:
        if recipe_folder and len(recipe_folder) > 0:
            tar.add(recipe_folder, arcname=node_identifier + "/" + "recipe_folder")
        else:
            print(f"no recipe in [{node_identifier}]")

    with tarfile.open(dir_path + "/source.tar", mode="x:") as tar:
        if source_folder and len(source_folder) > 0:
            tar.add(source_folder, arcname=node_identifier + "/" + "source_folder")
        else:
            print(f"no sources in [{node_identifier}]")

    with tarfile.open(dir_path + "/package.tar", mode="x:") as tar:
        if package_folder and len(package_folder) > 0:
            tar.add(package_folder, arcname=node_identifier + "/" + "package_folder")
        else:
            print(f"no package in [{node_identifier}]")


def dump_to_tar_wrapper(task: RepackageTaskDescription, output_dir_for_repackaged: str):
    global global_exception_info

    try:
        dump_to_tar(task, output_dir_for_repackaged)
    except Exception as e:
        import sys
        global_exception_info = (type(e), e, e.__traceback__)
        raise e

def sleep_for_a_bit(not_done):
    sleep(max(1, min(10, 2 * len(not_done))))


def throw_on_failure(futures: typing.MappingView):
    global global_exception_info
    if global_exception_info:
        for future in futures:
            future.cancel()
        raise global_exception_info[1].with_traceback(global_exception_info[2])
    for future in futures:
        try:
            future.result()
        except Exception as e:
            raise e


def rough_progress_report(futures_collector: Dict[concurrent.futures.Future, str]):
    not_done = [o for o in futures_collector.keys() if not o.done()]
    wait_start = strftime("%Y-%m-%dT%H:%M:%S")
    print(f"there are [{len(not_done)}] jobs in the queue.")
    if len(not_done) != 0:
        sleep_for_a_bit(not_done)
    else:
        return
    not_done = [o for o in futures_collector.keys() if not o.done()]
    while len(not_done) != 0:
        # check if something failed
        throw_on_failure(futures_collector.keys())

        # print stuff about which threads are running. a bit verbose, but better than nothing, maybe.
        print(f"waiting for [{len(not_done)}] job{"s" if len(not_done) > 1 else ""}" +
              f" at [{strftime("%Y-%m-%dT%H:%M:%S")}]; waiting since [{wait_start}].")
        for key in not_done:
            if len(futures_collector[key]) > 64:
                print(f"- [{futures_collector[key][:63]}]...")
            else:
                print(f"- [{futures_collector[key]}]")
        # we don't need a wall of text printed every second
        sleep_for_a_bit(not_done)
        not_done = [o for o in futures_collector.keys() if not o.done()]


def get_package_identifier_from_graph_node(graph_node: dict):
    # name/version@user/channel#rrev:pkgid#prev
    return get_package_identifier(graph_node["name"], graph_node["version"],
                                  graph_node["user"], graph_node["channel"],
                                  graph_node["rrev"], graph_node["package_id"], graph_node["prev"])


def get_package_identifier(name: str, version: str, user: str, channel: str, rrev: str, package_id: str,
                           prev: str):
    return (name or "") + "/" + (version or "") + "@" + \
        (user or "_") + "/" + (channel or "_") + \
        "#" + (rrev or "") + ":" + (package_id or "") + "#" + (prev or "")

def do_repackage(parsed: dict, output_dir_for_repackaged: str, worker_count: int):
    futures_collector = dict()
    with concurrent.futures.InterpreterPoolExecutor(max_workers=worker_count) as executor:
        package_identifier_to_task: Dict[str, RepackageTaskDescription] = dict()

        nodes = parsed["graph"]["nodes"]
        for graph_node in nodes.values():
            # check whether something already broke
            throw_on_failure(futures_collector.keys())

            ref = graph_node["ref"]

            if ref is None or len(ref) == 0:
                printerr("Warning: node has empty ref and will be skipped: " + json.dumps(graph_node))
                continue

            packager_identifier = get_package_identifier_from_graph_node(graph_node)

            # create task if it does not exist yet, otherwise just add to it
            if packager_identifier not in package_identifier_to_task:
                package_identifier_to_task[packager_identifier] =\
                    RepackageTaskDescription.new_with_identifiers_from_graph_node(graph_node)

            task = package_identifier_to_task[packager_identifier]

            # check that refs match (they always should, as prev should always be more precise than name, version, rrev)
            task.set_or_check_ref(ref)

            # record this graph node in the task object
            task.graph_nodes.add(dump_node_to_json(graph_node))

            # for each entry, we try to add this node's paths, which should be None or the same over same prev.
            task.set_or_check_recipe_folder(graph_node["recipe_folder"])
            task.set_or_check_source_folder(graph_node["source_folder"])
            task.set_or_check_package_folder(graph_node["package_folder"])

        print(f"processing created [{len(package_identifier_to_task.values())}] tasks from [{len(nodes)}] graph nodes.")
        for current_task in package_identifier_to_task.values():
            if current_task.ref != "conanfile" and not current_task.recipe_folder:
                printerr(f"task had [{current_task.recipe_folder}] for recipe_folder")
                raise RuntimeError(f"aborting submit: task [{task}] must be bad")
            # submit task as future; keep track of which future processes which node for better insight
            future = executor.submit(dump_to_tar_wrapper, current_task, output_dir_for_repackaged)
            futures_collector[future] = f"{current_task.node_identifier}"

        # now we are waiting for all futures to complete before the executor can close.
        # uncomment the progress report if you want it, it will wait and print excessive info, though.
        #rough_progress_report(futures_collector)

    # executor closed, check if any thread set an exception. note exceptions may clobber each other.
    throw_on_failure(futures_collector.keys())


def get_cpu_count(default_value: int = 1) -> int:
    cpu_count = default_value
    try:
        cpu_count = multiprocessing.cpu_count()
    except NotImplementedError as e:
        printerr(e)
        print(f"After exception: Falling back to default cpu count [{default_value}].")
    return cpu_count


def main():
    # input checks
    if (len(sys.argv)) != 3:
        printerr("give exactly ont input file to parse and one output dir for packages")
        print_usage_and_exit()

    # get input vars
    # input json (conan graph as output from 'conan install' command)
    input_json_filepath = sys.argv[1]
    # output dir where (repackaged) packages will be put
    output_dir = sys.argv[2]

    # ensure input file
    if not os.path.exists(input_json_filepath):
        printerr(f"given file [{sys.argv[1]}] does not exist")
        print_usage_and_exit()
    elif not os.path.isfile(input_json_filepath):
        printerr(f"given file [{sys.argv[1]}] is not a regular file")
        print_usage_and_exit()

    # prepare output dir
    if not os.path.exists(output_dir):
        print("creating output dirs at [" + output_dir + "]")
        os.mkdir(output_dir)
    if not os.path.isdir(output_dir):
        printerr(f"output dir at [{output_dir}] exists and is not a directory")
        raise NotADirectoryError("output_dir exists but is not a dir")

    # actual run...

    # parse the graph and work with it
    parsed = read_json(input_json_filepath)
    worker_count = get_cpu_count()

    # repackage every piece of information that we can find about every package in the graph
    do_repackage(parsed, output_dir, worker_count)

if __name__ == "__main__":
    main()
