load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//:lib/json.bzl", "json_bzl")

# We only use bazel_skylib for the unittest to exercise the yq binary pulled as a toolchain.  Note,
# there are better ways to yq() a thing; YQ being a common tool, it's fairly reliable to use it
# here, plus there should be fairly frequent updates

http_archive(
    name = "bazel_skylib",
    sha256 = "cd55a062e763b9349921f0f5db8c3933288dc8ba4f76dd9416aac68acee3cb94",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
    ],
)

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

# ==========================
# toolchains

# generates a virtual repository with:
# file: @versions_yq//:json.bzl defining YQ object that wraps attachments.json as a bazel dict
# file: @versions_yq//:BUILD defining register_toolchains()
json_bzl(
    name = "versions_yq",
    bzl_object = "YQ",
    json = "//toolchains/yq:attachments.json",
)

# This repo doesn't actually exist, but is created by json_bzl() above

load("@versions_yq//:json.bzl", "YQ", yq_register = "register_toolchains")

# now create an import definition of the repos defined by json_bzl() from attachments.json
# of course, they won't be read unless they're called in by dependency, and the http static
# resource/blob will cache in a basic HTTP(S)_PROXY cache or a bazel cache service
#
# we cannot easily scaffold/template this as the `build_file_content` is fairly variable

[http_archive(
    name = k,
    # NOTE: this generates the alias exploited in //toolchains/yq/BUILD.bazel: `tool = "@{}//:yq"`
    #     bazel run @yq_darwin_amd64//:yq -- --version
    #     bazel run @yq_darwin_arm64//:yq -- --version
    build_file_content = "\n".join([
        """alias(name="yq", actual="//:{}", visibility = ["//visibility:public"])""".format(k),
        "",  # readability during debug
    ]),
    sha256 = v["sha256"],
    url = v["url"],
) for k, v in YQ.items()]

# json_bzl() creates a toolchain registration func based on the keys of the attachments.json file.
# The same naming -- the key of the dict is used as the name of the repository -- is used in
# //toolchains/yq:BUILD

yq_register()
