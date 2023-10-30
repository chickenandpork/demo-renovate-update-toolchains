# demo-renovate-update-toolchains

This is an example of using Renovate(Bot) to keep our OS/arch-specific toolchains updated.

The key take-away is PR https://github.com/chickenandpork/demo-renovate-update-toolchains/pull/5
where we can see that RenovateBot matches the `sha256` for existing files from release `v4.34.1`
and replaces with corresponding `sha256` for the current `v4.35.2`.  The power here is that this
solution scales: a few directories with JSON-based metadata and you're off-to-the races.

Another facet of this solution is that you have a maintained, parsable structure of version and
sha256 information that can be reused elsewhere.  For example, I have one project that is simply a
lightweight IDP-like toolkit for Mac that provides multi-arch binaries for all the tools we need.
This converts our install of a new Mac, and ongoing maintenance, to "1. install package; 2. there
is no step 2, all the tools are present".  Indeed, this MacOS package avoids the Brewfiles and the
transitive dependencies ("who knew that the CLI would change so much when the MySQL lib it needed
changed?") that can add churn and entropy to your reliable build environment.  Using a solution
similar to this meant I had the version info for sanity scripts and other checks as well, reducing
Write-Everything-Twice errors.

If you don't have a bunch of binaries to track and keep updated, and lack the need for the metadata
to be used elsewhere, the complexity and indirection here might be too much techdebt to justify.

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
load("//:lib/json.bzl", "json_bzl")

# We use bazel_skylib for unittesting but it's not significant to this example

# generates a virtual repository with:
# file: @versions_yq//:json.bzl defining YQ object that wraps attachments.json as a bazel dict
# file: @versions_yq//:BUILD defining register_toolchains()

json_bzl(
    name = "versions_yq",
    bzl_object = "YQ",
    json = "//toolchains/yq:attachments.json", # <-- manually-maintained data
)

# fake resource is created by json_bzl() above
load("@versions_yq//:json.bzl", "YQ", yq_register = "register_toolchains")

# now create an import definition of the repos defined by json_bzl() from attachments.json
# of course, they won't be read unless they're called in by dependency, and the http static
# resource/blob will cache in a basic HTTP(S)_PROXY cache or a bazel cache service
#
# we cannot easily scaffold/template this as the `build_file_content` is fairly variable

[http_archive(
    name = k,
    # NOTE: this generates the alias exploited in //toolchains/yq/BUILD.bazel: `tool = "@{}//:yq"`
    build_file_content = "\n".join([
        """alias(name="yq", actual="//:{}", visibility = ["//visibility:public"])""".format(k),
        "",  # readability during debug
    ]),
    sha256 = v["sha256"],
    url = v["url"],
) for k, v in YQ.items()]

# register the toolchains from @versions_yq
yq_register()
```

json_bzl() reads `//toolchains/yq:attachments.json` and creates:
 - `@versions_yq//:json.bzl` defines YQ object that lightly wraps the attachment metadata
 - `@versions_yq//:BUILD` defines register_toolchains()

The YQ object is used for a list-comprehension of `http_archive()` registration of external
resources, but defines a custom `BUILD` file resource to allow access to, and define a convenience
alias for, the binaries and tools within (`yq` in this case, but done as arch/os tuples such as
`yq_darwin_amd64`, but we remap those to `@{arch/os name}//:yq` for convenience

... so that defines the name, checksum, URL, and a simple `BUILD` file that makes it easier to use
the tools (by exposing the `yq` binary) and gives us simple test commands
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

# yq_toolchain() rule uses the implementation to instantiate YqToolchainInfo provider filled in with
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

First, we collect a few small metadata items that would be listed in a query of `releases` in the
api.github.com/project/ path into a file committed to code: this means the data we used cannot be
mutable and change without a PR/MR committed; it also means we don't incur a network pull for every
build, but use cached content.

(`attachments.json` file, conventionally a `//toolchains/yq/attachments.json`)
```
{
    "yq_darwin_amd64": {
        "os": "osx",
        "cpu": "x86_64",
        "sha256": "52dd4639d5aa9dda525346dd74efbc0f017d000b1570b8fa5c8f983420359ef9",
        "url": "https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_darwin_amd64.tar.gz"
    },
    "yq_darwin_arm64": {
        "os": "osx",
        "cpu": "aarch64",
        "sha256": "52dd4639d5aa9dda525346dd74efbc0f017d000b1570b8fa5c8f983420359ef9",
        "url": "https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_darwin_amd64.tar.gz"
    }
}
```

### Use the single-definition of the metadata to build toolchains

(`BUILD` File, conventionally a `//toolchains/yq/BUILD.bazel`)
```
load(":yq_toolchain.bzl", "yq_toolchain")  # load the rule()
load("@versions_yq//:json.bzl", "YQ")  # generated in WORKSPACE from attachments.json

# define a specific type to trigger type-checking
toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

# instance of yq_toolchain (strongly-typed toolchain struct) for each key/value in attachments
[
    yq_toolchain(
        name = "{}".format(k),

        tool = "@{}//:yq".format(k),
        visibility = ["//visibility:public"],
    )
    for k, v in YQ.items()
]

# toolchains: list-comprehension, one toolchain per key/value in attachments.json

[
    toolchain(
        name = "{}_toolchain".format(k),
        exec_compatible_with = [
            "@platforms//os:{}".format(v["os"]),
            "@platforms//cpu:{}".format(v["cpu"]),
        ],
        target_compatible_with = [
            "@platforms//os:{}".format(v["os"]),
            "@platforms//cpu:{}".format(v["cpu"]),
        ],
        toolchain = ":{}".format(k),  # yq_toolchain(name=k) matches YQ.keys()
        toolchain_type = ":toolchain_type",  # `toolchain_type(...)` above
    )
    for k, v in YQ.items()
]
```

... so for each key/value in attachments.json representing a binary resource, the appropriate
os/arch mapped to that release is transposed to a bazel-style registration mapping the build/exec
profile to the appropriate tool.  The `toolchain` maps out "on this architecture, which binary
should I use?" to a strongly-typed toolchain that includes a dependency on the remote resource.

Of course, Bazel doesn't pull it in until it's needed.  The resulting pulled repo, and the binary
within that we need, gets mapped to the `tool` attribute of the `yqinfo` attribute of the toolchain
specific to the YqToolchain descendent type of the toolchain.

Fwew.

This turns a bunch of cut-n-paste into a repeated instance of the same function, mapped in
consistent ways, for our use on-demand.

We can see that -- going forward -- we just need to maintain that `attachments.json` file as the
attachments of a GitHub release or the artifacts of a GitLab build evolve.
