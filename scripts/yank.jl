# Add `yanked = true` to one version in a package's Versions.toml, editing
# the file textually so existing formatting and ordering are preserved.
#
# Environment: PACKAGE (name), VERSION (x.y.z)

using TOML

name = ENV["PACKAGE"]
version = ENV["VERSION"]

index = TOML.parsefile("Registry.toml")
uuid = findfirst(p -> p["name"] == name, index["packages"])
uuid === nothing && error("package $name not found in Registry.toml")
path = joinpath(index["packages"][uuid]["path"], "Versions.toml")

lines = readlines(path)
header = "[\"$version\"]"
start = findfirst(l -> strip(l) == header, lines)
start === nothing && error("version $version not found in $path")
stop = findnext(l -> startswith(strip(l), "["), lines, start + 1)
stop = stop === nothing ? length(lines) + 1 : stop

section = strip.(lines[(start + 1):(stop - 1)])
if "yanked = true" in section
    @info "$name v$version is already yanked"
else
    insert!(lines, start + count(!isempty, section) + 1, "yanked = true")
    write(path, join(lines, "\n") * "\n")
    @info "Yanked $name v$version"
end
