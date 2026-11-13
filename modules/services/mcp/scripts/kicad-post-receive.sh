# A push into a KiCad project (servers/kicad.nix) checks its files out (receive.denyCurrentBranch updateInstead) as
# whoever pushed, with their umask: make what they now own group-writable, so the project's server and sync can edit
# it. Push hooks run in .git.
cd ..
find . -path ./.git -prune -o -user "$(id -u)" ! -perm -g+w -exec chmod g+w {} +
