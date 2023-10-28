# type/struct/class helps to strongly-type later rules
YqToolchainInfo = provider(
    doc = "Yq toolchain defines a single binary",
    fields = {
        "tool": "Yq executable binary",  # you could also use "yq" rather than "tool"
    },
)

# "implementation" of the rule instantiates a YQ toolchain filled in with the passed value
def _yq_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        yqinfo = YqToolchainInfo(
            tool = ctx.attr.tool,
        ),
    )

    # returning the TemplateVariableInfo here still isn't helping, still need yq_var
    variables = platform_common.TemplateVariableInfo(
        {"YQ": ctx.attr.tool.files.to_list()[0].path},
    )

    return [toolchain_info, variables]

# yq_toolchain() rule uses the implemantation to instantiate YqToolchainInfo provider filled in with
# the given tool (an os/arch-specific "yq" binary)
yq_toolchain = rule(
    implementation = _yq_toolchain_impl,
    attrs = {
        "tool": attr.label(allow_single_file = True, doc = "yq binary"),
    },
)

# This `yq_var` rule simply loads a TemplateVariableInfo with the YQ variable from the toolchain so
# that we can insert in a genrule during testing.  It has nothing to do with the actual toolchain
# logic, only the testing -- because if you truly cared, you'd unittest it, right ?
def _yq_var_impl(ctx):
    # ctx.toolchains* filled in by toolchain resolution
    # bazel test test/... --toolchain_resolution_debug=//toolchains/yq:toolchain_type

    tool = ctx.toolchains["//toolchains/yq:toolchain_type"].yqinfo.tool.files.to_list()[0]

    return [
        platform_common.TemplateVariableInfo({
            "YQ": tool.path,
        }),
        DefaultInfo(files = depset([tool])),
    ]

yq_var = rule(
    implementation = _yq_var_impl,
    toolchains = ["//toolchains/yq:toolchain_type"],  # triggers toolchain resolution
)
