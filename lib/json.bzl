def json_bzl_impl(repository_ctx):
    data = json.decode(repository_ctx.read(repository_ctx.path(repository_ctx.attr.json)))
    base = repository_ctx.attr.toolchain_base

    config_lines = [
        "# {} construct based on contents of {}".format(repository_ctx.attr.bzl_object, repository_ctx.attr.json),
        "",
        "{} = {}".format(repository_ctx.attr.bzl_object, data),
        "",
        "def register_toolchains():",
        "    native.register_toolchains(",
    ] + [
        """        "{}:{}_toolchain",""".format(base, k)
        for k in data.keys()
    ] + [
        "    )",
        "",
    ]

    repository_ctx.file(repository_ctx.attr.bzl_name, "\n".join(config_lines))
    repository_ctx.file("BUILD", "")

json_bzl = repository_rule(
    attrs = {
        "json": attr.label(mandatory = True),
        "bzl_name": attr.string(default = "json.bzl"),
        "bzl_object": attr.string(default = "JSON"),
        "toolchain_base": attr.string(default = "@//toolchains/yq"),
    },
    implementation = json_bzl_impl,
)
