load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "66ffd9315665bfaafc96b52278f57c7e2dd09f5ede279ea6d39b2be471e7e3aa",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.4.2/bazel-skylib-1.4.2.tar.gz",
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.4.2/bazel-skylib-1.4.2.tar.gz",
    ],
)

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

# toolchains

http_archive(
    name = "yq_darwin_amd64",
    # The BUILD file is really a few convenience aliases (may remove later, or convert to list)
    # You can test whether it's resolving for your architecture using:

    #     bazel run @yq_darwin_amd64//:yq -- --version
    build_file_content = "\n".join([
        """alias(name="yq", actual="//:yq_darwin_amd64", visibility = ["//visibility:public"])""",
        "",  # readability during debug
    ]),
    sha256 = "52dd4639d5aa9dda525346dd74efbc0f017d000b1570b8fa5c8f983420359ef9",
    urls = [
        "https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_darwin_amd64.tar.gz",
    ],
)

register_toolchains(
    "//toolchains/yq:yq_darwin_amd64_toolchain",
)
