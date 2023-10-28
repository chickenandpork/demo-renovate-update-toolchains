# demo-renovate-update-toolchains

This is an example of using Renovate(Bot) to keep our OS/arch-specific toolchains updated

## Toolchains

### Bazel

I'm a big fan of Bazel: I can concisely define a build process, state resources with sha256 hashes
(which are validated when retrieved), cache derived objects, federate the cache in a cluster,
federate the build steps across a cluster, cross-compile, etc.

Really, Bazel is like `USL make` on steroids.

...and there's iBazel.

### Bazel Toolchains

Bazel can look at the build architecture, and either build the necessary tools, or download the
appropriate tool (OS, architecture) to use in the build.  This means I could, say, refer to
`opentofu`, and get a functional `opentofu` binary whether I'm on linux, mac, windows -- and NOT
download the tools I don't need.

This convenience is through `toolchains`: perhaps named for wrapping compiler toolchains, this
allows us to markup a binary or set of binaries/tools/resources as functional on certain OS and
architectures, and allow `bazel` to go get it.  Of course, if it's not needed in a dependency of
the build, bazel won't download it.

...so we can add cross-platform capability to our tightly-defined build process by describing the
tools as toolchains.

## Marking up a Tool

We need to tell `bazel` where the tool comes from, what parts we want, and what platform attributes
it matches

### Source of Tools

Bazel needs to know a few URLs to get the tool, a name for it, and the signature to ensure accuracy
(which can detect supply-line poisoning).  That markup looks like this (traditional non-module
format):

(`WORKSPACE` or load()ed `.bzl` file))
```
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

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
```

... so that defines the name, checksum, URL, and a simple `BUILD` file that makes it easier to use
the tools (by exposing the `yq` binary) and gives us 	 simple test command
(`bazel run @yq_darwin_amd64//:yq -- --version`) to ensure the basic retrieval works.

### Define the Tool Components

Bazel uses a "provider" to define a special type.  This isn't so strongly-types as a class in an OO
language, more like attributes that give meaning and labels to components.

(`.bzl` file loaded into a `BUILD` file: `yq_toolchain.bzl`)
```
# type/struct/class helps to strongly-type later rules
YqToolchainInfo = provider(
    doc = "Yq toolchain defines a single binary",
    fields = {
        "tool": "Yq executable binary", # you could also use "yq" rather than "tool"
    },
)

# "implementation" of the rule instantiates a YQ toolchain filled in with the passed value
def _yq_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        yqinfo = YqToolchainInfo(
            tool = ctx.attr.tool,
        ),
    )

    # the working code has some attempts to fill a TemplateVariableInfo and return as composite but
    # that's not effective yet -- see the `yq_var()` workaround in toolchains/yq/yq_toolchain.bzl
    return [toolchain_info]

# yq_toolchain() rule uses the implemantation to instantiate YqToolchainInfo provider filled in with
# the given tool (an os/arch-specific "yq" binary)
yq_toolchain = rule(
    implementation = _yq_toolchain_impl,
    attrs = {
        "tool": attr.label(allow_single_file = True, doc = "yq binary"),
    },
)
```

That may look like a bunch of boilerplate, but this allows us to wrote a bunch of `yq_toolchain()`
structures per-http_archive and each wraps the given architecture's `yq` binary.

### Match the toolchain to an architecture/OS pair

(`BUILD` File, conventionally a `//toolchains/yq/BUILD.bazel`)
```
load(":yq_toolchain.bzl", "yq_toolchain")  # load the rule()

# define a specific type to trigger type-checking
toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

yq_toolchain(
    name = "yq_darwin_amd64",  # local scope doesn't clash with @yq_darwin_amd64

    # tool matches the `bazel run @yq_darwin_amd64//:yq -- --version` binary noted above in
    # (WORKSPACE) `http_archive( name = "yq_darwin_amd64", ...)` with `alias( name="yq", ...)`
    # in `build_file_content`.  Note that the alias in that content both maps the consistent `:yq`
    # to the `:yq_darwin_amd64` arch-specific binary in each tarball archive, but also opens up
    # visibility

    tool = "@yq_darwin_amd64//:yq",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "yq_darwin_amd64_toolchain",
    exec_compatible_with = [
        "@platforms//os:osx",  # yep, "osx" not "darwin"
        "@platforms//cpu:x86_64",  # yep, "x86_64" not "amd64"
    ],
    target_compatible_with = [
        "@platforms//os:osx",
        "@platforms//cpu:x86_64",
    ],

    # matches `yq_toolchain( name = "yq_darwin_amd64", ...` in this file
    toolchain = ":yq_darwin_amd64",
    toolchain_type = ":toolchain_type",  # `toolchain_type(...)` above
)
```

... so what this says is that when we're on an osx/x86_64, the toolchain is a `:toolchain_type`
(scoped to the directory: `//toolchains/yq:toolchain_type`) returned by the rule
`yq_toolchain( name = "yq_darwin_amd64", ...)` which is a `yqinfo.tool` pointing to where the
binary is unpacked and ready when needed.  fwew.  A bunch of fairly cut-n-pastable boilerplate.


