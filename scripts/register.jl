# Register the package in the working directory into the registry clone at
# ENV["REGISTRY_PATH"], create the version tag, and report the version via
# GITHUB_OUTPUT. Safe to re-run: each step checks whether it already happened.
#
# Environment:
#   BUMP           patch | minor | major | x.y.z | current   (default: patch)
#   REGISTRY_PATH  path to a pushable clone of the registry
#   GITHUB_OUTPUT  optional; receives `version=x.y.z`

using TOML
using LocalRegistry

shellout(cmd::Cmd) = strip(read(cmd, String))

function target_version(current::VersionNumber, bump::AbstractString)
    bump == "current" && return current
    bump == "patch" && return VersionNumber(current.major, current.minor, current.patch + 1)
    bump == "minor" && return VersionNumber(current.major, current.minor + 1, 0)
    bump == "major" && return VersionNumber(current.major + 1, 0, 0)
    return VersionNumber(bump)
end

function set_version!(path::AbstractString, v::VersionNumber)
    lines = readlines(path)
    i = findfirst(l -> startswith(l, "version"), lines)
    i === nothing && error("no version field in $path")
    lines[i] = "version = \"$v\""
    write(path, join(lines, "\n") * "\n")
end

# Another package may register concurrently; rebase and retry the push.
function push_registry(registry::AbstractString)
    branch = shellout(`git -C $registry rev-parse --abbrev-ref HEAD`)
    for attempt in 1:5
        success(run(ignorestatus(`git -C $registry push origin $branch`))) && return
        @warn "registry push rejected (attempt $attempt); rebasing"
        run(`git -C $registry pull --rebase origin $branch`)
    end
    error("could not push registry commit after 5 attempts")
end

project = TOML.parsefile("Project.toml")
name = project["name"]
uuid = project["uuid"]
current = VersionNumber(project["version"])
version = target_version(current, get(ENV, "BUMP", "current"))
branch = shellout(`git rev-parse --abbrev-ref HEAD`)
registry = abspath(ENV["REGISTRY_PATH"])
tag = "v$version"

@info "Registering" name uuid current version branch

run(`git config --global user.name jool-bot`)
run(`git config --global user.email bot@jool.space`)

# Step 1: version bump commit on the package repo.
run(`git fetch origin $branch`)
remote_project = TOML.parse(shellout(`git show $("origin/$branch:Project.toml")`))
remote_version = VersionNumber(remote_project["version"])
if remote_version == version
    @info "Project.toml on origin/$branch is already at $version; using that commit"
    run(`git reset --hard $("origin/$branch")`)
elseif current == version
    isempty(shellout(`git status --porcelain`)) || error("working tree is dirty")
    run(`git push origin $branch`)
else
    set_version!("Project.toml", version)
    run(`git commit -am $tag`)
    run(`git push origin $branch`)
end

commit = shellout(`git rev-parse HEAD`)
tree = shellout(`git rev-parse $("HEAD^{tree}")`)

# Step 2: registry entry.
index = TOML.parsefile(joinpath(registry, "Registry.toml"))
entry = get(get(index, "packages", Dict()), uuid, nothing)
registered = false
if entry !== nothing
    versions = TOML.parsefile(joinpath(registry, entry["path"], "Versions.toml"))
    if haskey(versions, string(version))
        registered_tree = versions[string(version)]["git-tree-sha1"]
        if registered_tree == tree
            @info "$name $tag already registered; skipping"
        else
            # Registered from an earlier commit (e.g. only CI files changed
            # since a partially failed run). The tag must point at the
            # commit the registry describes, so find it in the history.
            history = split(shellout(`git log --format=$("%H %T") HEAD`), '\n')
            i = findfirst(l -> endswith(l, registered_tree), history)
            i === nothing && error(
                "$name $tag is registered with tree $registered_tree, " *
                "which is not in this branch's history (HEAD tree: $tree)")
            commit = first(split(history[i]))
            @info "$name $tag was registered from commit $commit; tagging that"
        end
        registered = true
    end
end
if !registered
    LocalRegistry.register(pwd(); registry, commit=true, push=false)
    push_registry(registry)
end

# Step 3: tag.
if isempty(shellout(`git ls-remote origin $("refs/tags/$tag")`))
    run(`git tag -a $tag -m $tag $commit`)
    run(`git push origin $tag`)
else
    @info "tag $tag already on origin; skipping"
end

output = get(ENV, "GITHUB_OUTPUT", nothing)
output === nothing || open(io -> println(io, "version=$version"), output, "a")
@info "Done" name version commit
