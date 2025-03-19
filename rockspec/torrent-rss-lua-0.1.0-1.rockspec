package = "torrent-rss-lua"
version = "0.1.0-1"
source = {
    url = "git+https://github.com/SirZenith/torrent-rss-lua.git",
    tag = version
}
description = {
    detailed = [[A torrent RSS subscription manage script written in lua.]],
    homepage = "https://github.com/SirZenith/torrent-rss-lua",
    license = "MIT/X11"
}
dependencies = {
    "lua >= 5.1, < 5.5",
    "base64 >= 1.5",
    "xml2lua >= 1.6",
    "lua-argparse >= 0.2.0",
    "luasec >= 1.3",
    "luasocket >= 3.0",
    "lunajson >= 1.2.3",
}
build = {
    type = "builtin",
    modules = {}
}
