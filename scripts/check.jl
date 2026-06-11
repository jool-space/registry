# Structural consistency check for the registry. No dependencies beyond TOML.

using TOML

failures = String[]
fail(msg) = push!(failures, msg)

index = TOML.parsefile("Registry.toml")
for key in ("name", "uuid", "repo")
    haskey(index, key) || fail("Registry.toml missing `$key`")
end

for (uuid, entry) in get(index, "packages", Dict{String,Any}())
    path = entry["path"]
    prefix = "$(entry["name"]) ($path):"
    isdir(path) || (fail("$prefix directory missing"); continue)

    package = TOML.parsefile(joinpath(path, "Package.toml"))
    package["name"] == entry["name"] || fail("$prefix Package.toml name mismatch")
    package["uuid"] == uuid || fail("$prefix Package.toml uuid mismatch")
    haskey(package, "repo") || fail("$prefix Package.toml missing repo")

    versions = TOML.parsefile(joinpath(path, "Versions.toml"))
    isempty(versions) && fail("$prefix no versions")
    for (v, info) in versions
        tree = get(info, "git-tree-sha1", "")
        occursin(r"^[0-9a-f]{40}$", tree) || fail("$prefix $v bad git-tree-sha1")
        try
            VersionNumber(v)
        catch
            fail("$prefix $v is not a valid version number")
        end
    end

    for file in ("Deps.toml", "Compat.toml")
        full = joinpath(path, file)
        isfile(full) && try
            TOML.parsefile(full)
        catch e
            fail("$prefix $file does not parse: $e")
        end
    end
end

if isempty(failures)
    n = length(get(index, "packages", Dict()))
    println("Registry consistent ($n packages)")
else
    foreach(println, failures)
    error("$(length(failures)) consistency failure(s)")
end
