-- Artists, covers, playlists and the Library's rows, FoxyOS 18.3, and
-- genres, charts, mixes, Replayed and search, FoxyOS 18.4: a real Bank Core
-- and Vault, five Cloud Servers and the Music Server.
--
-- A song credited "Ana Fox & Kit" makes two Artist Profiles. Ana takes hers
-- as her own (nobody owned it) and Kit cannot have it; a song uploaded with a
-- cover keeps it. Playing a song puts it in Recently Played and counts its
-- artists' listeners for the day; a radio playing it is a Radio Hit and puts
-- the radio on the artist's profile. Playlists are public unless their owner
-- says not; favorites are a heart away. MUSIC_HOME has it all, in rows.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local net = require("lib.net")
local music = require("lib.music")
local util = require("lib.util")

local world = require("cloud_harness").start(harness, bank)
local as = world.as
local POCKET, MUSIC_ID, PLAYER_ID = world.pocket, 30, 40
world.beatAll()
local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local noa = bank.register("Noa Hare", "4321")
bank.fund(ana, 1000)

local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()

local function ask(action, payload, from)
    return as(from or POCKET, net.ask, MUSIC_ID, config.music_protocol, action, payload, 3)
end
local function must(action, payload, from)
    local answer, err, code = ask(action, payload, from)
    assert(answer, action .. ": " .. tostring(code) .. " " .. tostring(err))
    return answer
end
local function refused(code, action, payload, from)
    local answer, err, got = ask(action, payload, from)
    assert(not answer and got == code, action .. " should be " .. code .. ", was "
        .. tostring(got) .. " " .. tostring(err))
end
local function cover(digit)
    local rows = {}
    for index = 1, 12 do rows[index] = string.rep(digit, 12) end
    return table.concat(rows, "/")
end
-- FoxyOS 18.4: square, 12x12. The 16x12 covers of 18.3 are not covers any more.
local wide = {}
for index = 1, 12 do wide[index] = string.rep("e", 16) end
assert(util.validCover(cover("e")) and not util.validCover("eeee/eeee")
    and not util.validCover(table.concat(wide, "/")))

-- Profiles from credits -------------------------------------------------------------------------

local duet = as(MUSIC_ID, server.library.import, { title = "Two Foxes", artist = "Ana Fox & Kit",
    kind = "song", uploader_name = "Foxy Records", genre = "Lo-fi" }, string.rep("d", 12000))
local solo = as(MUSIC_ID, server.library.import, { title = "Den Beat", artist = "Kit",
    kind = "song", uploader_name = "Foxy Records", genre = "lo-FI" }, string.rep("k", 12000))
assert(duet.genre == solo.genre and server.state.genres[duet.genre].name == "Lo-fi",
    "one genre, however it is typed")
local listed = must("MUSIC_ARTISTS", {}).artists
assert(#listed == 2, "Ana Fox and Kit, made by the credit: " .. #listed)
local kitProfile = must("MUSIC_ARTIST", { name = "kit" }).artist
assert(kitProfile.songs_count == 2 and not kitProfile.claimed, "Kit's two songs, nobody's profile")

-- Ana takes hers; Kit cannot.
local mine = must("MUSIC_ARTIST_SAVE", { session_token = ana.token, name = "Ana Fox",
    bio = "Foxes, mostly", cover = cover("1") }).artist
assert(mine.claimed and mine.songs_count == 1 and mine.bio == "Foxes, mostly",
    "her profile, with the song that credited it")
refused("NAME_TAKEN", "MUSIC_ARTIST_SAVE", { session_token = kit.token, name = "Ana Fox" })
refused("BAD_COVER", "MUSIC_ARTIST_SAVE", { session_token = ana.token, cover = "nope" })
assert(must("MUSIC_MY_ARTIST", { session_token = ana.token }).artist.name == "Ana Fox")

-- An upload with a cover, crediting somebody new.
local body = string.rep("u", 9000)
refused("BAD_GENRE", "MUSIC_UPLOAD_BEGIN", { session_token = kit.token, title = "Night Run",
    artist = "Kit, Noa Hare", size = #body })
local began = must("MUSIC_UPLOAD_BEGIN", { session_token = kit.token, title = "Night Run",
    artist = "Kit, Noa Hare", size = #body, cover = cover("b"), genre = "Synthwave" })
assert(as(POCKET, music.upload, began.plan, body, config.cloud_protocol))
local uploaded = must("MUSIC_UPLOAD_DONE", { session_token = kit.token,
    upload_id = began.upload_id }).track
assert(uploaded.cover == cover("b") and #uploaded.artists == 2 and uploaded.genre == "Synthwave",
    "its cover, both artists and a genre made for it")
assert(must("MUSIC_ARTIST", { name = "Noa Hare" }).artist.songs_count == 1, "Noa has a profile now")
-- Its cover is the uploader's to change, not anybody's.
refused("NOT_YOURS", "MUSIC_TRACK_EDIT", { session_token = noa.token,
    track_id = uploaded.track_id, cover = cover("e") })
must("MUSIC_TRACK_EDIT", { session_token = kit.token, track_id = uploaded.track_id,
    cover = cover("e") })
-- Ana is credited on Two Foxes, so she may change its cover.
must("MUSIC_TRACK_EDIT", { session_token = ana.token, track_id = duet.track_id, cover = cover("4") })

-- Listening -------------------------------------------------------------------------------------

local hello = must("MUSIC_HELLO", { session_token = noa.token, label = "Noa's" }, PLAYER_ID)
local function player(action, payload)
    payload = payload or {}
    payload.player_token = hello.player_token
    return must(action, payload, PLAYER_ID)
end
player("MUSIC_CONTROL", { command = "play", track_id = duet.track_id })
assert(player("MUSIC_STREAM").item.cover == cover("4"), "the cover, for Now Playing")
assert(must("MUSIC_ARTIST", { name = "Kit" }).artist.listeners_today == 1, "Noa heard Kit today")
assert(must("MUSIC_ARTIST", { name = "Ana Fox" }).artist.listeners_today == 1)

-- A radio plays Den Beat: a Radio Hit, and Kit's profile names the radio.
local r = as(MUSIC_ID, server.radio.create, "Foxy State", "lime")
r.songs = { solo.track_id }
as(MUSIC_ID, server.radio.now, r)
local kitFull = must("MUSIC_ARTIST", { name = "Kit" }).artist
assert(kitFull.radios[1] and kitFull.radios[1].name == "Foxy State", "on the radio")

-- Favorites and playlists -------------------------------------------------------------------------

assert(must("MUSIC_FAVORITE", { session_token = noa.token, track_id = uploaded.track_id }).favorite)
refused("SIGN_IN", "MUSIC_FAVORITE", { track_id = uploaded.track_id })
local made = must("MUSIC_PLAYLIST_SAVE", { session_token = noa.token, name = "Night Drive",
    cover = cover("a"), tracks = { uploaded.track_id, duet.track_id, "T999" } }).playlist
assert(made.public and #made.tracks == 2 and made.cover == cover("a"), "public, and only real songs")
refused("NOT_YOURS", "MUSIC_PLAYLIST_SAVE", { session_token = kit.token,
    playlist_id = made.playlist_id, name = "Mine now" })
local secret = must("MUSIC_PLAYLIST_SAVE", { session_token = noa.token, name = "Secret",
    cover = cover("f"), tracks = { solo.track_id }, public = false }).playlist
refused("NOT_FOUND", "MUSIC_PLAYLIST", { session_token = kit.token, playlist_id = secret.playlist_id })
assert(must("MUSIC_PLAYLIST", { session_token = kit.token, playlist_id = made.playlist_id })
    .playlist.songs_count == 2, "anybody sees a public one")
player("MUSIC_CONTROL", { command = "play", track_id = uploaded.track_id,
    queue = { uploaded.track_id, duet.track_id }, playlist_id = made.playlist_id })
assert(server.state.playlists[made.playlist_id].plays == 1)

-- The rows -----------------------------------------------------------------------------------------

local function rows(who)
    local out = {}
    for _, row in ipairs(must("MUSIC_HOME", { session_token = who.token }).rows) do out[row.id] = row end
    return out
end
local noaRows = rows(noa)
local order = {}
for _, row in ipairs(must("MUSIC_HOME", { session_token = noa.token }).rows) do order[#order + 1] = row.id end
assert(table.concat(order, ",") == "recent,favorites,replayed,new,popular,radio,charts,mixes,playlists",
    "hers on top, then everybody's, then playlists: " .. table.concat(order, ","))
assert(noaRows.new.tracks[1].title == "Night Run", "newest first")
assert(noaRows.popular.tracks[1].track_id == duet.track_id, "the one played most")
assert(noaRows.favorites.tracks[1].track_id == uploaded.track_id, "her heart")
assert(noaRows.radio.tracks[1].track_id == solo.track_id and #noaRows.radio.tracks == 1,
    "Radio Hits: only what radios played")
assert(noaRows.recent.tracks[1].track_id == duet.track_id, "what she played")
assert(#noaRows.playlists.playlists == 1, "everybody's public ones: her private one is on Me")
local profile = must("MUSIC_PROFILE", { session_token = noa.token })
assert(#profile.playlists == 2 and profile.name == "Noa Hare" and profile.favorites == 1,
    "Me: every playlist of hers")
local kitRows = rows(kit)
assert(#kitRows.playlists.playlists == 1 and #kitRows.favorites.tracks == 0
    and #kitRows.recent.tracks == 0, "Kit sees the public one, and nothing of Noa's own")
must("MUSIC_PLAYLIST_DELETE", { session_token = noa.token, playlist_id = secret.playlist_id })
assert(#must("MUSIC_PROFILE", { session_token = noa.token }).playlists == 1)

-- Replayed, FoxyOS 18.4: what she plays over and over -- twice is enough.
assert(#noaRows.replayed.tracks == 0, "once is not replayed")
for _ = 1, 2 do
    player("MUSIC_CONTROL", { command = "play", track_id = solo.track_id })
    player("MUSIC_STREAM")
end
noaRows = rows(noa)
assert(noaRows.replayed.tracks[1].track_id == solo.track_id, "Den Beat, on repeat")

-- Genres, mixes and charts --------------------------------------------------------------------

local genres = must("MUSIC_GENRES").genres
assert(genres[1].name == "Lo-fi" and genres[1].songs == 2 and genres[2].name == "Synthwave",
    "the biggest genre first")
local lofi = must("MUSIC_GENRE", { genre_id = duet.genre })
assert(#lofi.tracks == 2 and lofi.mix.playlist_id == "MIX:" .. duet.genre
    and lofi.mix.name == "Lo-fi Mix" and util.validCover(lofi.mix.cover), "a mix, with Foxy's cover")
-- Twenty songs in a genre: the mix is fifteen of them, the same all day.
for index = 1, 20 do
    as(MUSIC_ID, server.library.import, { title = "Wave " .. index, artist = "Pia",
        kind = "song", uploader_name = "Foxy Records", genre = "Synthwave" }, string.rep("w", 600))
end
local synth = server.state.genre_names["synthwave"]
local function mixOf()
    local ids = {}
    for _, track in ipairs(must("MUSIC_PLAYLIST", { session_token = noa.token,
        playlist_id = "MIX:" .. synth }).playlist.tracks) do ids[#ids + 1] = track.track_id end
    return table.concat(ids, ",")
end
local today = mixOf()
local _, count = today:gsub(",", "")
assert(count + 1 == 15 and mixOf() == today, "fifteen of twenty-one, the same all day")
local realDay = os.day
os.day = function() return realDay("ingame") + 1 end
assert(mixOf() ~= today, "mixed again the next day")
os.day = realDay
-- The charts: Den Beat was played most this week, and Kit is its artist.
local top = must("MUSIC_PLAYLIST", { session_token = noa.token, playlist_id = "TOP:SONGS" }).playlist
assert(top.auto and top.name == "Top Songs" and top.tracks[1].track_id == solo.track_id,
    "Top Songs, from the week's plays")
local artists = must("MUSIC_PLAYLIST", { session_token = noa.token, playlist_id = "TOP:ARTISTS" })
    .playlist
assert(artists.tracks[1].track_id == solo.track_id, "Kit's biggest song, for the biggest artist")
noaRows = rows(noa)
assert(#noaRows.charts.playlists == 2 and #noaRows.mixes.playlists == 2, "on the Music tab")
refused("NOT_YOURS", "MUSIC_PLAYLIST_SAVE", { session_token = noa.token, playlist_id = "TOP:SONGS",
    name = "Mine" })
-- A song from before genres gets one from its artist.
local old = as(MUSIC_ID, server.library.import, { title = "Old Tune", artist = "Kit",
    kind = "song", uploader_name = "Foxy Records" }, string.rep("o", 600))
assert(old.genre == nil)
must("MUSIC_TRACK_EDIT", { session_token = kit.token, track_id = uploaded.track_id, genre = "Lo-fi" })
assert(server.state.tracks[uploaded.track_id].genre == duet.genre, "moved to Lo-fi")

-- Search: artists, songs and genres.
local found = must("MUSIC_SEARCH", { query = "wave" })
assert(#found.tracks == 20 and #found.artists == 0, "twenty Waves")
found = must("MUSIC_SEARCH", { query = "kit" })
assert(found.artists[1].name == "Kit" and #found.tracks >= 1, "Kit, and Kit's songs")
assert(#must("MUSIC_SEARCH", { query = "synth" }).genres == 1)
refused("BAD_QUERY", "MUSIC_SEARCH", { query = "  " })

-- A Music Player asks as its owner: Noa's rows, by its player token.
local fromPlayer = must("MUSIC_HOME", { player_token = hello.player_token }, PLAYER_ID)
assert(fromPlayer.rows[1].tracks[1].track_id == solo.track_id, "her Recently Played")

-- 18.3's covers are wiped once, on the first start of 18.4.
server.state.tracks[duet.track_id].cover = table.concat(wide, "/")
server.state.playlists[made.playlist_id].cover = cover("a")
server.state.cover_size = nil
-- Restarted on what it saved (the harness keeps nothing on disk).
local loadTable = util.loadTable
util.loadTable = function() return util.copy(server.state) end
local again = world.attach(MUSIC_ID + 1, "music_server.lua", config.music_protocol, "music_server")
util.loadTable = loadTable
assert(again.state.tracks[duet.track_id] and again.state.cover_size == 12, "restarted, and marked")
assert(again.state.tracks[duet.track_id].cover == nil
    and again.state.playlists[made.playlist_id].cover == nil, "every old cover gone")

io.write("host_music_catalog_test: OK\n")
