load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoArchive",
)

AppEngineProjectInfo = provider(
    fields = {
        'project': 'A name of Appengine project',
    }
)

def _appengine_project_impl(ctx):
    return [AppEngineProjectInfo(project = ctx.attr.project)]  

appengine_project = rule(
    _appengine_project_impl,
    attrs = {
        'project': attr.string()
    }
)

SourceFileInfo = provider(
    fields = {
        'files' : 'list of source files',
        'exists' : 'dict of source file paths',
    }
)

def _merge_dep_files(files, exists, dep):
    dep_files = dep[SourceFileInfo].files
    dep_exists = dep[SourceFileInfo].exists

    if len(dep_files) == 0:
        return

    if len(files) == 0:
        files.extend(dep_files)
        exists.update(dep_exists)
    else:
        for f in dep_files:
            if f.path not in exists:
                files.append(f)
                exists[f.path] = True

def _go_cumulative_source_aspect_impl(target, ctx):
    files = []
    exists = {}

    # Get the source files from our dependencies.
    for dep in ctx.rule.attr.deps:
        _merge_dep_files(files, exists, dep)

    for dep in ctx.rule.attr.embed:
        _merge_dep_files(files, exists, dep)

    # Make sure the rule has a srcs attribute.
    if hasattr(ctx.rule.attr, 'srcs'):
        # Iterate through the source files and merge them into the list.
        for src in ctx.rule.attr.srcs:
            for f in src.files.to_list():
                if not f.path.startswith("external/") and f.path not in exists:
                    files.append(f)
                    exists[f.path] = True

    return [SourceFileInfo(files = files, exists = exists)]

_go_cumulative_source_aspect = aspect(
    implementation = _go_cumulative_source_aspect_impl,
    attr_aspects = [
        'embed',
        'deps'
    ],
    attrs = {}
)

def _go_cumulative_sources_impl(ctx):
    source_file_info = None
    for dep in ctx.attr.deps:
        source_file_info = dep[SourceFileInfo]

    return [source_file_info]

_go_cumulative_sources = rule(
    _go_cumulative_sources_impl,
    attrs = {
        'deps' : attr.label_list(aspects = [_go_cumulative_source_aspect]),
    },  
)

def _list_to_files(list):
    files = []
    for f in list:
        files.extend(f.files.to_list())
    return files

def _go_appengine_base_impl(ctx):

#    print(ctx.attr.binary)
#    print(ctx.attr.binary[GoArchive].runfiles.files)
#    print(ctx.attr.binary[DefaultInfo].data_runfiles.files)
    configs = ""
    configfiles = []
    for config in ctx.attr.configs:
        filelist = config.files.to_list()

        for f in filelist:
            configs = configs + " \"" + f.basename + "\""
            configfiles.append(f)

    args = ""
    project = ctx.attr.project[AppEngineProjectInfo].project

    args = "-q --project=%s" % project
 
    extra_ignore = "\n".join(ctx.attr.ignore)

    substitutions = {
        "%{gcloud_path}": ctx.attr.gcloud.files_to_run.executable.short_path,
        "%{workspace_name}": ctx.workspace_name,
        "%{configs}": configs,
        "%{args}": args,
        "%{target_name}": ctx.attr.name,
        "%{extra_ignore}": extra_ignore,
    }

#    print(ctx.attr.srcs[SourceFileInfo].files)
    go_src_files = depset(ctx.attr.srcs[SourceFileInfo].files)

    runfiles = ctx.runfiles(transitive_files = go_src_files).merge(
        ctx.runfiles(_list_to_files(ctx.attr.configs))
    ).merge(
        ctx.runfiles(_list_to_files(ctx.attr.data))
    ).merge(
        ctx.runfiles(_list_to_files(ctx.attr.gomods))
    ).merge(
        ctx.attr.binary[GoArchive].runfiles
    ).merge(
        ctx.runfiles([ctx.outputs.gcloudignore])
    )

    ctx.actions.expand_template(
        output = ctx.outputs.deploy_sh,
        template = ctx.file._deploy_template,
        substitutions = substitutions,
        is_executable = True,
    )
    ctx.actions.expand_template(
        output = ctx.outputs.tar_sh,
        template = ctx.file._tar_template,
        substitutions = substitutions,
        is_executable = True,
    )
    ctx.actions.expand_template(
        output = ctx.outputs.gcloudignore,
        template = ctx.file._ignore_template,
        substitutions = substitutions,
        is_executable = False,
    )

    return [DefaultInfo(runfiles = runfiles)]

go_appengine_base = rule(
    _go_appengine_base_impl,
    attrs = {
        "srcs": attr.label(),
        "data": attr.label_list(allow_files = True),
        "binary": attr.label(),
        "configs": attr.label_list(allow_files = [".yaml"]),
        "project": attr.label(),
        "gomods": attr.label_list(allow_files = True),
        "gcloud": attr.label(default = Label("@io_halaco_google_cloud_sdk//:gcloud")),
        "ignore": attr.string_list(default = []),
        "_deploy_template": attr.label(
            default = Label("//tools/bazel/appengine:go_deploy_template"),
            allow_single_file = True,
        ),
        "_tar_template": attr.label(
            default = Label("//tools/bazel/appengine:go_tar_template"),
            allow_single_file = True,
        ),
        "_ignore_template": attr.label(
            default = Label("//tools/bazel/appengine:gcloudignore_template"),
            allow_single_file = True,
        ),
    },
    executable = False,
    outputs = {
        "deploy_sh": "%{name}_deploy.sh",
        "tar_sh": "%{name}_tar.sh",
        "gcloudignore": ".gcloudignore",
    },
)

def go_appengine(name, binary, project, configs, data = [], ignore = []):

    cumulative_sources_rule_name = name + "_go_cumulative_sources"

    _go_cumulative_sources(
        name = cumulative_sources_rule_name,
        deps = [binary],
    )

    go_appengine_base(
        name = name,
        srcs = cumulative_sources_rule_name,
        binary = binary,
        configs = configs,
        project = project,
        data = data,
        gomods = ["go.mod", "go.sum"],
        ignore = ignore,
    )

    native.sh_binary(
        name = "%s.deploy" % name,
        srcs = ["%s_deploy.sh" % name],
        data = [
            name,
            "@io_halaco_google_cloud_sdk//:gcloud",
        ],
    )

    native.sh_binary(
        name = "%s.tar" % name,
        srcs = ["%s_tar.sh" % name],
        data = [
            name,
        ],
    )
