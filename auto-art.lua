-- Kraken Galactic Block Art Maker  (block 10962)
-- Commands: /art  /pos1  /pos2  /artpause  /artresume  /artcancel  /artmap  /artstatus
-- Reads PNG, JPG (baseline), GIF and BMP itself. Anything else (WebP, AVIF, progressive JPG,
-- huge files...) goes through the online converter when it is switched on in /art.
-- The Kraken colour dialog is learned automatically from the first block you build.

local Dec = (function()
-- ============================================================
--  image decoders (pure Lua): PNG, JPEG (baseline), GIF, BMP
--  Dec.decode(bytes, targetW, targetH) -> grid | nil, error
--  grid = { w, h, r = {}, g = {}, b = {}, a = {} }  (index = y*w + x + 1, x/y from 0)
-- ============================================================
local Dec = {}
local floor = math.floor
local P2 = {}
for i = 0, 40 do P2[i] = 2 ^ i end

Dec.tickCount = 0
Dec.tickEvery = 40
Dec.yield = function() end   -- the main script replaces this with a short Sleep

local function tick()
    Dec.tickCount = Dec.tickCount + 1
    if Dec.tickCount >= Dec.tickEvery then
        Dec.tickCount = 0
        Dec.yield()
    end
end

local function u16be(s, i) local a, b = s:byte(i, i + 1) return (a or 0) * 256 + (b or 0) end
local function u32be(s, i) local a, b, c, d = s:byte(i, i + 3) return (a or 0) * 16777216 + (b or 0) * 65536 + (c or 0) * 256 + (d or 0) end
local function u16le(s, i) local a, b = s:byte(i, i + 1) return (a or 0) + (b or 0) * 256 end
local function u32le(s, i) local a, b, c, d = s:byte(i, i + 3) return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216 end
local function s32le(s, i) local n = u32le(s, i) if n >= 2147483648 then n = n - 4294967296 end return n end

-- ------------------------------------------------------------
--  resampler: every decoder feeds pixels here
-- ------------------------------------------------------------
local function newSink(sw, sh, tw, th)
    local S = { sw = sw, sh = sh, tw = tw, th = th }
    local store = (sw <= tw and sh <= th)
    S.store = store
    if store then
        local pix = {}
        S.put = function(px, py, r, g, b, a)
            pix[py * sw + px + 1] = ((a * 256 + r) * 256 + g) * 256 + b
        end
        S.finish = function()
            local out = { w = tw, h = th, r = {}, g = {}, b = {}, a = {} }
            for ty = 0, th - 1 do
                local sy = floor((ty + 0.5) * sh / th)
                if sy >= sh then sy = sh - 1 end
                for tx = 0, tw - 1 do
                    local sx = floor((tx + 0.5) * sw / tw)
                    if sx >= sw then sx = sw - 1 end
                    local v = pix[sy * sw + sx + 1]
                    local i = ty * tw + tx + 1
                    if v then
                        local b = v % 256; v = floor(v / 256)
                        local g = v % 256; v = floor(v / 256)
                        local r = v % 256; v = floor(v / 256)
                        out.r[i], out.g[i], out.b[i], out.a[i] = r, g, b, v
                    else
                        out.r[i], out.g[i], out.b[i], out.a[i] = 0, 0, 0, 0
                    end
                end
            end
            return out
        end
    else
        local xmap, ymap = {}, {}
        for px = 0, sw - 1 do xmap[px] = floor(px * tw / sw) end
        for py = 0, sh - 1 do ymap[py] = floor(py * th / sh) end
        local n = tw * th
        local sr, sg, sb, sa, cnt = {}, {}, {}, {}, {}
        for i = 1, n do sr[i], sg[i], sb[i], sa[i], cnt[i] = 0, 0, 0, 0, 0 end
        S.put = function(px, py, r, g, b, a)
            local i = ymap[py] * tw + xmap[px] + 1
            sr[i] = sr[i] + r * a
            sg[i] = sg[i] + g * a
            sb[i] = sb[i] + b * a
            sa[i] = sa[i] + a
            cnt[i] = cnt[i] + 1
        end
        S.finish = function()
            local out = { w = tw, h = th, r = {}, g = {}, b = {}, a = {} }
            local have = {}
            for i = 1, n do
                local c = cnt[i]
                if c > 0 then
                    have[i] = true
                    local a = sa[i]
                    if a > 0 then
                        out.r[i] = floor(sr[i] / a + 0.5)
                        out.g[i] = floor(sg[i] / a + 0.5)
                        out.b[i] = floor(sb[i] / a + 0.5)
                    else
                        out.r[i], out.g[i], out.b[i] = 0, 0, 0
                    end
                    out.a[i] = floor(a / c + 0.5)
                end
            end
            -- cells no source pixel landed in (one axis grows, the other shrinks): copy a neighbour
            for ty = 0, th - 1 do
                local base = ty * tw
                local last
                for tx = 0, tw - 1 do
                    local i = base + tx + 1
                    if have[i] then last = i
                    elseif last then
                        out.r[i], out.g[i], out.b[i], out.a[i] = out.r[last], out.g[last], out.b[last], out.a[last]
                        have[i] = "f"
                    end
                end
                last = nil
                for tx = tw - 1, 0, -1 do
                    local i = base + tx + 1
                    if have[i] == true then last = i
                    elseif not have[i] and last then
                        out.r[i], out.g[i], out.b[i], out.a[i] = out.r[last], out.g[last], out.b[last], out.a[last]
                        have[i] = "f"
                    end
                end
            end
            for ty = 0, th - 1 do
                for tx = 0, tw - 1 do
                    local i = ty * tw + tx + 1
                    if not have[i] then
                        local src
                        for d = 1, th do
                            local up, dn = ty - d, ty + d
                            if up >= 0 and have[up * tw + tx + 1] then src = up * tw + tx + 1 break end
                            if dn < th and have[dn * tw + tx + 1] then src = dn * tw + tx + 1 break end
                        end
                        if src then
                            out.r[i], out.g[i], out.b[i], out.a[i] = out.r[src], out.g[src], out.b[src], out.a[src]
                        else
                            out.r[i], out.g[i], out.b[i], out.a[i] = 0, 0, 0, 0
                        end
                    end
                end
            end
            return out
        end
    end
    return S
end

-- ------------------------------------------------------------
--  inflate (zlib / deflate), streaming: every output byte goes to emit()
-- ------------------------------------------------------------
local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function buildHuff(lengths, n)
    local count = {}
    for i = 0, 15 do count[i] = 0 end
    local maxb = 0
    for i = 0, n - 1 do
        local l = lengths[i] or 0
        count[l] = count[l] + 1
        if l > maxb then maxb = l end
    end
    if maxb == 0 then return { maxb = 1, tbl = {} } end
    count[0] = 0
    local nextc, code = {}, 0
    for l = 1, 15 do
        code = (code + count[l - 1]) * 2
        nextc[l] = code
    end
    local tbl = {}
    local size = P2[maxb]
    for sym = 0, n - 1 do
        local l = lengths[sym] or 0
        if l > 0 then
            local c = nextc[l]
            nextc[l] = c + 1
            local r, cc = 0, c
            for _ = 1, l do
                r = r * 2 + cc % 2
                cc = floor(cc / 2)
            end
            local step = P2[l]
            local k = r
            while k < size do
                tbl[k] = sym * 16 + l
                k = k + step
            end
        end
    end
    return { maxb = maxb, tbl = tbl }
end

local FIXED_LIT, FIXED_DIST
local function fixedTables()
    if FIXED_LIT then return FIXED_LIT, FIXED_DIST end
    local l = {}
    for i = 0, 143 do l[i] = 8 end
    for i = 144, 255 do l[i] = 9 end
    for i = 256, 279 do l[i] = 7 end
    for i = 280, 287 do l[i] = 8 end
    FIXED_LIT = buildHuff(l, 288)
    local d = {}
    for i = 0, 29 do d[i] = 5 end
    FIXED_DIST = buildHuff(d, 30)
    return FIXED_LIT, FIXED_DIST
end

function Dec.inflate(s, pos, emit)
    local bitbuf, bitcnt = 0, 0
    local win, wp = {}, 0
    local function need(n)
        while bitcnt < n do
            local b = s:byte(pos) or 0
            pos = pos + 1
            bitbuf = bitbuf + b * P2[bitcnt]
            bitcnt = bitcnt + 8
        end
    end
    local function bits(n)
        if n == 0 then return 0 end
        need(n)
        local v = bitbuf % P2[n]
        bitbuf = floor(bitbuf / P2[n])
        bitcnt = bitcnt - n
        return v
    end
    local function decode(h)
        local mb = h.maxb
        need(mb)
        local e = h.tbl[bitbuf % P2[mb]]
        if not e then error("bad huffman code") end
        local l = e % 16
        bitbuf = floor(bitbuf / P2[l])
        bitcnt = bitcnt - l
        return floor(e / 16)
    end
    local function out(b)
        win[wp % 32768] = b
        wp = wp + 1
        emit(b)
    end
    local final
    repeat
        final = bits(1)
        local typ = bits(2)
        if typ == 0 then
            pos = pos - floor(bitcnt / 8)
            bitbuf, bitcnt = 0, 0
            local len = u16le(s, pos)
            pos = pos + 4
            for _ = 1, len do
                out(s:byte(pos) or 0)
                pos = pos + 1
            end
        elseif typ == 1 or typ == 2 then
            local lit, dist
            if typ == 1 then
                lit, dist = fixedTables()
            else
                local hlit, hdist, hclen = bits(5) + 257, bits(5) + 1, bits(4) + 4
                local cl = {}
                for i = 0, 18 do cl[i] = 0 end
                for i = 1, hclen do cl[CLORDER[i]] = bits(3) end
                local clh = buildHuff(cl, 19)
                local lengths, i = {}, 0
                while i < hlit + hdist do
                    local sym = decode(clh)
                    if sym < 16 then
                        lengths[i] = sym
                        i = i + 1
                    else
                        local rep, val = 0, 0
                        if sym == 16 then
                            val = lengths[i - 1] or 0
                            rep = 3 + bits(2)
                        elseif sym == 17 then
                            rep = 3 + bits(3)
                        else
                            rep = 11 + bits(7)
                        end
                        for _ = 1, rep do
                            lengths[i] = val
                            i = i + 1
                        end
                    end
                end
                local ll, dl = {}, {}
                for k = 0, hlit - 1 do ll[k] = lengths[k] or 0 end
                for k = 0, hdist - 1 do dl[k] = lengths[hlit + k] or 0 end
                lit = buildHuff(ll, hlit)
                dist = buildHuff(dl, hdist)
            end
            while true do
                local sym = decode(lit)
                if sym < 256 then
                    out(sym)
                elseif sym == 256 then
                    break
                else
                    sym = sym - 256
                    local len = LBASE[sym] + bits(LEXT[sym])
                    local ds = decode(dist) + 1
                    local d = DBASE[ds] + bits(DEXT[ds])
                    for _ = 1, len do
                        out(win[(wp - d) % 32768] or 0)
                    end
                end
            end
        else
            error("bad deflate block")
        end
    until final == 1
end

-- ------------------------------------------------------------
--  PNG
-- ------------------------------------------------------------
local PNG_SIG = "\137PNG\r\n\26\n"

local function pngDecode(data, tw, th)
    if data:sub(1, 8) ~= PNG_SIG then return nil, "not a PNG" end
    local pos = 9
    local w, h, depth, ctype, interlace
    local plte, trns, idat = nil, nil, {}
    while pos + 7 <= #data do
        local len = u32be(data, pos)
        local typ = data:sub(pos + 4, pos + 7)
        local body = data:sub(pos + 8, pos + 7 + len)
        if typ == "IHDR" then
            w, h, depth, ctype, interlace = u32be(body, 1), u32be(body, 5), body:byte(9), body:byte(10), body:byte(13)
        elseif typ == "PLTE" then plte = body
        elseif typ == "tRNS" then trns = body
        elseif typ == "IDAT" then idat[#idat + 1] = body
        elseif typ == "IEND" then break end
        pos = pos + 12 + len
    end
    if not w or w < 1 or h < 1 then return nil, "PNG header missing" end
    local channelsOf = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }
    local channels = channelsOf[ctype]
    if not channels then return nil, "unknown PNG colour type" end
    if ctype == 3 and not plte then return nil, "PNG palette missing" end
    local z = table.concat(idat)
    if #z < 3 then return nil, "PNG has no image data" end

    local sink = newSink(w, h, tw, th)
    local put = sink.put
    local bpix = channels * depth
    local bpp = floor((bpix + 7) / 8)

    local passes
    if interlace == 1 then
        passes = { { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 }, { 2, 0, 4, 4 }, { 0, 2, 2, 4 }, { 1, 0, 2, 2 }, { 0, 1, 1, 2 } }
    else
        passes = { { 0, 0, 1, 1 } }
    end

    -- transparency helpers
    local trnsGray, trnsR, trnsG, trnsB
    local palA = {}
    if trns then
        if ctype == 0 and #trns >= 2 then trnsGray = u16be(trns, 1)
        elseif ctype == 2 and #trns >= 6 then trnsR, trnsG, trnsB = u16be(trns, 1), u16be(trns, 3), u16be(trns, 5)
        elseif ctype == 3 then
            for i = 1, #trns do palA[i - 1] = trns:byte(i) end
        end
    end
    local pal = {}
    if plte then
        for i = 0, floor(#plte / 3) - 1 do
            pal[i] = { plte:byte(i * 3 + 1), plte:byte(i * 3 + 2), plte:byte(i * 3 + 3) }
        end
    end
    local maxv = P2[depth] - 1

    -- state of the row machine
    local passIdx = 0
    local pw, ph, xs, ys, xstep, ystep, rowBytes
    local rowIdx, fill = 0, 0
    local cur, prev = {}, {}
    local finished = false

    local function nextPass()
        while true do
            passIdx = passIdx + 1
            local p = passes[passIdx]
            if not p then finished = true return end
            xs, ys, xstep, ystep = p[1], p[2], p[3], p[4]
            pw = (w > xs) and floor((w - xs + xstep - 1) / xstep) or 0
            ph = (h > ys) and floor((h - ys + ystep - 1) / ystep) or 0
            if pw > 0 and ph > 0 then
                rowBytes = floor((pw * bpix + 7) / 8)
                rowIdx, fill = 0, 0
                for i = 1, rowBytes do prev[i] = 0 end
                return
            end
        end
    end
    nextPass()

    local function emitRow(row, py)
        for x = 0, pw - 1 do
            local px = xs + x * xstep
            local r, g, b, a
            if depth == 8 then
                if ctype == 6 then
                    local i = x * 4 + 1
                    r, g, b, a = row[i], row[i + 1], row[i + 2], row[i + 3]
                elseif ctype == 2 then
                    local i = x * 3 + 1
                    r, g, b, a = row[i], row[i + 1], row[i + 2], 255
                    if trnsR and r == trnsR % 256 and g == trnsG % 256 and b == trnsB % 256 then a = 0 end
                elseif ctype == 0 then
                    r = row[x + 1]; g, b, a = r, r, 255
                    if trnsGray and r == trnsGray % 256 then a = 0 end
                elseif ctype == 4 then
                    r = row[x * 2 + 1]; g, b, a = r, r, row[x * 2 + 2]
                else
                    local c = pal[row[x + 1]] or { 0, 0, 0 }
                    r, g, b = c[1], c[2], c[3]
                    a = palA[row[x + 1]] or 255
                end
            elseif depth == 16 then
                if ctype == 6 then
                    local i = x * 8 + 1
                    r, g, b, a = row[i], row[i + 2], row[i + 4], row[i + 6]
                elseif ctype == 2 then
                    local i = x * 6 + 1
                    r, g, b, a = row[i], row[i + 2], row[i + 4], 255
                    if trnsR and row[i] * 256 + row[i + 1] == trnsR and row[i + 2] * 256 + row[i + 3] == trnsG
                        and row[i + 4] * 256 + row[i + 5] == trnsB then a = 0 end
                elseif ctype == 0 then
                    local i = x * 2 + 1
                    r = row[i]; g, b, a = r, r, 255
                    if trnsGray and row[i] * 256 + row[i + 1] == trnsGray then a = 0 end
                else
                    local i = x * 4 + 1
                    r = row[i]; g, b, a = r, r, row[i + 2]
                end
            else
                -- 1, 2 or 4 bits per sample (gray or palette)
                local bit = x * depth
                local byte = row[floor(bit / 8) + 1]
                local v = floor(byte / P2[8 - depth - bit % 8]) % P2[depth]
                if ctype == 3 then
                    local c = pal[v] or { 0, 0, 0 }
                    r, g, b = c[1], c[2], c[3]
                    a = palA[v] or 255
                else
                    r = floor(v * 255 / maxv + 0.5); g, b, a = r, r, 255
                    if trnsGray and v == trnsGray then a = 0 end
                end
            end
            put(px, py, r or 0, g or 0, b or 0, a or 255)
        end
    end

    local function processRow()
        local ft = cur[1]
        local c = cur
        -- unfilter in place; sample i of the row is c[i + 1]
        if ft == 1 then
            for i = bpp + 1, rowBytes do c[i + 1] = (c[i + 1] + c[i + 1 - bpp]) % 256 end
        elseif ft == 2 then
            for i = 1, rowBytes do c[i + 1] = (c[i + 1] + prev[i]) % 256 end
        elseif ft == 3 then
            for i = 1, rowBytes do
                local left = (i > bpp) and c[i + 1 - bpp] or 0
                c[i + 1] = (c[i + 1] + floor((left + prev[i]) / 2)) % 256
            end
        elseif ft == 4 then
            for i = 1, rowBytes do
                local a = (i > bpp) and c[i + 1 - bpp] or 0
                local b = prev[i]
                local cc = (i > bpp) and prev[i - bpp] or 0
                local p = a + b - cc
                local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - cc)
                local pr
                if pa <= pb and pa <= pc then pr = a elseif pb <= pc then pr = b else pr = cc end
                c[i + 1] = (c[i + 1] + pr) % 256
            end
        end
        local row = {}
        for i = 1, rowBytes do
            row[i] = c[i + 1]
            prev[i] = c[i + 1]
        end
        emitRow(row, ys + rowIdx * ystep)
        tick()
    end

    local function emit(b)
        if finished then return end
        fill = fill + 1
        cur[fill] = b
        if fill == rowBytes + 1 then
            processRow()
            fill = 0
            rowIdx = rowIdx + 1
            if rowIdx >= ph then nextPass() end
        end
    end

    local ok, err = pcall(Dec.inflate, z, 3, emit)
    if not ok and not finished then return nil, "PNG data is damaged: " .. tostring(err) end
    return sink.finish()
end

-- ------------------------------------------------------------
--  JPEG (baseline / sequential Huffman)
-- ------------------------------------------------------------
local ZZ = {
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
}

local IDCT_COS = {}
local function idctCos(n)
    if IDCT_COS[n] then return IDCT_COS[n] end
    local t = {}
    for x = 0, n - 1 do
        t[x] = {}
        for u = 0, n - 1 do
            local c = (u == 0) and (1 / math.sqrt(2)) or 1
            t[x][u] = c * math.cos((2 * x + 1) * u * math.pi / (2 * n))
        end
    end
    IDCT_COS[n] = t
    return t
end

local function jpegBuildLut(counts, syms)
    local lut = {}
    local code, k = 0, 1
    for l = 1, 16 do
        for _ = 1, counts[l] do
            local base = code * P2[16 - l]
            local v = syms[k] * 32 + l
            for j = 0, P2[16 - l] - 1 do lut[base + j] = v end
            code = code + 1
            k = k + 1
        end
        code = code * 2
    end
    return lut
end

local function jpegProbe(data)
    local pos, n = 3, #data
    while pos < n do
        while pos <= n and data:byte(pos) ~= 0xFF do pos = pos + 1 end
        while pos <= n and data:byte(pos) == 0xFF do pos = pos + 1 end
        local m = data:byte(pos)
        if not m then return nil end
        pos = pos + 1
        if m >= 0xC0 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC then
            return u16be(data, pos + 5), u16be(data, pos + 3), m
        elseif m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7) or m == 0 then
            -- no length
        elseif m == 0xD9 then
            return nil
        else
            pos = pos + u16be(data, pos)
        end
    end
    return nil
end

local function jpegDecode(data, tw, th)
    local n = #data
    local pos = 3
    local qt, dcT, acT = {}, {}, {}
    local frame, restart, adobe = nil, 0, nil
    local scanStart, scanComps
    while pos < n do
        while pos <= n and data:byte(pos) ~= 0xFF do pos = pos + 1 end
        while pos <= n and data:byte(pos) == 0xFF do pos = pos + 1 end
        local m = data:byte(pos)
        if not m then break end
        pos = pos + 1
        if m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7) or m == 0 then
            -- no payload
        elseif m == 0xD9 then
            break
        else
            local len = u16be(data, pos)
            local seg, segEnd = pos + 2, pos + len
            if m == 0xDB then
                local p = seg
                while p < segEnd do
                    local pt = data:byte(p)
                    local pq, tq = floor(pt / 16), pt % 16
                    p = p + 1
                    local q = {}
                    for i = 1, 64 do
                        if pq == 0 then q[i] = data:byte(p) p = p + 1
                        else q[i] = u16be(data, p) p = p + 2 end
                    end
                    qt[tq] = q
                end
            elseif m == 0xC4 then
                local p = seg
                while p < segEnd do
                    local tc = data:byte(p)
                    local class, id = floor(tc / 16), tc % 16
                    p = p + 1
                    local counts, total = {}, 0
                    for i = 1, 16 do counts[i] = data:byte(p + i - 1) total = total + counts[i] end
                    p = p + 16
                    local syms = {}
                    for i = 1, total do syms[i] = data:byte(p + i - 1) end
                    p = p + total
                    local lut = jpegBuildLut(counts, syms)
                    if class == 0 then dcT[id] = lut else acT[id] = lut end
                end
            elseif m == 0xC0 or m == 0xC1 then
                local prec = data:byte(seg)
                if prec ~= 8 then return nil, "JPEG precision not supported" end
                frame = { h = u16be(data, seg + 1), w = u16be(data, seg + 3), comps = {} }
                local nc = data:byte(seg + 5)
                for i = 1, nc do
                    local o = seg + 6 + (i - 1) * 3
                    local hv = data:byte(o + 1)
                    frame.comps[i] = { id = data:byte(o), h = floor(hv / 16), v = hv % 16, tq = data:byte(o + 2) }
                end
            elseif m == 0xC2 then
                return nil, "progressive JPEG"
            elseif m >= 0xC3 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC then
                return nil, "this JPEG type is not supported"
            elseif m == 0xDD then
                restart = u16be(data, seg)
            elseif m == 0xEE then
                if data:sub(seg, seg + 4) == "Adobe" then adobe = data:byte(seg + 11) end
            elseif m == 0xDA then
                local ns = data:byte(seg)
                scanComps = {}
                for i = 1, ns do
                    local cs, tt = data:byte(seg + 1 + (i - 1) * 2), data:byte(seg + 2 + (i - 1) * 2)
                    scanComps[i] = { id = cs, td = floor(tt / 16), ta = tt % 16 }
                end
                scanStart = segEnd
                break
            end
            pos = segEnd
        end
    end
    if not frame or not scanStart then return nil, "JPEG header incomplete" end
    local nc = #frame.comps
    if nc ~= 1 and nc ~= 3 then return nil, "this JPEG colour mode is not supported" end
    if #scanComps ~= nc then return nil, "multi-scan JPEG" end
    local w, h = frame.w, frame.h
    if w < 1 or h < 1 then return nil, "JPEG size invalid" end

    local hmax, vmax = 1, 1
    for _, c in ipairs(frame.comps) do
        if c.h > hmax then hmax = c.h end
        if c.v > vmax then vmax = c.v end
    end
    -- pick the smallest scale that still gives at least the target size
    local sc = 8
    for _, cand in ipairs({ 1, 2, 4, 8 }) do
        if math.ceil(w * cand / 8) >= tw and math.ceil(h * cand / 8) >= th then sc = cand break end
    end
    local ow, oh = math.ceil(w * sc / 8), math.ceil(h * sc / 8)
    local sink = newSink(ow, oh, tw, th)
    local put = sink.put
    local COS = idctCos(sc)

    for i, c in ipairs(frame.comps) do
        local sc_c = scanComps[i]
        c.dc = dcT[sc_c.td]
        c.ac = acT[sc_c.ta]
        c.q = qt[c.tq]
        if not c.dc or not c.ac or not c.q then return nil, "JPEG tables missing" end
        c.pred = 0
        c.plane = {}
        c.pw = c.h * sc
        c.ph = c.v * sc
    end

    local dpos = scanStart
    local acc, nb = 0, 0
    local function fillBits()
        while nb < 16 do
            local b = data:byte(dpos)
            if b == nil then
                b = 0
            elseif b == 0xFF then
                if data:byte(dpos + 1) == 0 then dpos = dpos + 2 else b = 0 end
            else
                dpos = dpos + 1
            end
            acc = acc * 256 + b
            nb = nb + 8
        end
    end
    local function decodeSym(lut)
        fillBits()
        local e = lut[floor(acc / P2[nb - 16])]
        if not e then error("bad JPEG code") end
        local l = e % 32
        nb = nb - l
        acc = acc % P2[nb]
        return floor(e / 32)
    end
    local function receive(t)
        if t == 0 then return 0 end
        fillBits()
        local v = floor(acc / P2[nb - t])
        nb = nb - t
        acc = acc % P2[nb]
        return v
    end

    local blk = {}
    local tmp = {}
    local function decodeBlock(c)
        for i = 0, 63 do blk[i] = 0 end
        local t = decodeSym(c.dc)
        local diff = 0
        if t > 0 then
            diff = receive(t)
            if diff < P2[t - 1] then diff = diff - P2[t] + 1 end
        end
        c.pred = c.pred + diff
        blk[0] = c.pred * c.q[1]
        local k = 1
        while k < 64 do
            local rs = decodeSym(c.ac)
            local r, s = floor(rs / 16), rs % 16
            if s == 0 then
                if r == 15 then k = k + 16 else break end
            else
                k = k + r
                if k > 63 then break end
                local v = receive(s)
                if v < P2[s - 1] then v = v - P2[s] + 1 end
                blk[ZZ[k + 1]] = v * c.q[k + 1]
                k = k + 1
            end
        end
    end

    -- scaled inverse DCT of blk -> plane at (bx, by)
    local function idct(c, bx, by)
        local stride = c.pw
        local plane = c.plane
        if sc == 1 then
            local v = blk[0] / 8 + 128
            plane[by * stride + bx + 1] = v < 0 and 0 or (v > 255 and 255 or v)
            return
        end
        for v = 0, sc - 1 do
            local any = false
            for u = 0, sc - 1 do
                if blk[v * 8 + u] ~= 0 then any = true break end
            end
            if any then
                for x = 0, sc - 1 do
                    local s = 0
                    local cx = COS[x]
                    for u = 0, sc - 1 do
                        local f = blk[v * 8 + u]
                        if f ~= 0 then s = s + cx[u] * f end
                    end
                    tmp[v * sc + x] = s
                end
            else
                for x = 0, sc - 1 do tmp[v * sc + x] = 0 end
            end
        end
        for y = 0, sc - 1 do
            local cy = COS[y]
            for x = 0, sc - 1 do
                local s = 0
                for v = 0, sc - 1 do s = s + cy[v] * tmp[v * sc + x] end
                local val = s / 4 + 128
                if val < 0 then val = 0 elseif val > 255 then val = 255 end
                plane[(by + y) * stride + bx + x + 1] = val
            end
        end
    end

    local mcuW, mcuH = 8 * hmax, 8 * vmax
    local mcusX, mcusY = math.ceil(w / mcuW), math.ceil(h / mcuH)
    local oW, oH = sc * hmax, sc * vmax      -- output pixels per MCU
    local rgbMode = (nc == 3 and adobe == 0)
    local count = 0
    local c1, c2, c3 = frame.comps[1], frame.comps[2], frame.comps[3]

    for my = 0, mcusY - 1 do
        for mx = 0, mcusX - 1 do
            if restart > 0 and count > 0 and count % restart == 0 then
                nb, acc = 0, 0
                while dpos < n do
                    local b = data:byte(dpos)
                    local b2 = data:byte(dpos + 1)
                    if b == 0xFF and b2 and b2 >= 0xD0 and b2 <= 0xD7 then dpos = dpos + 2 break end
                    dpos = dpos + 1
                end
                for _, c in ipairs(frame.comps) do c.pred = 0 end
            end
            count = count + 1
            for _, c in ipairs(frame.comps) do
                for bv = 0, c.v - 1 do
                    for bh = 0, c.h - 1 do
                        decodeBlock(c)
                        idct(c, bh * sc, bv * sc)
                    end
                end
            end
            local baseX, baseY = mx * oW, my * oH
            for oy = 0, oH - 1 do
                local Y = baseY + oy
                if Y < oh then
                    for ox = 0, oW - 1 do
                        local X = baseX + ox
                        if X < ow then
                            local y1 = c1.plane[floor(oy * c1.v / vmax) * c1.pw + floor(ox * c1.h / hmax) + 1]
                            local r, g, b
                            if nc == 1 then
                                r, g, b = y1, y1, y1
                            else
                                local y2 = c2.plane[floor(oy * c2.v / vmax) * c2.pw + floor(ox * c2.h / hmax) + 1]
                                local y3 = c3.plane[floor(oy * c3.v / vmax) * c3.pw + floor(ox * c3.h / hmax) + 1]
                                if rgbMode then
                                    r, g, b = y1, y2, y3
                                else
                                    local cb, cr = y2 - 128, y3 - 128
                                    r = y1 + 1.402 * cr
                                    g = y1 - 0.344136 * cb - 0.714136 * cr
                                    b = y1 + 1.772 * cb
                                end
                            end
                            r = floor(r + 0.5); g = floor(g + 0.5); b = floor(b + 0.5)
                            if r < 0 then r = 0 elseif r > 255 then r = 255 end
                            if g < 0 then g = 0 elseif g > 255 then g = 255 end
                            if b < 0 then b = 0 elseif b > 255 then b = 255 end
                            put(X, Y, r, g, b, 255)
                        end
                    end
                end
            end
        end
        tick()
    end
    return sink.finish()
end

-- ------------------------------------------------------------
--  GIF (first frame)
-- ------------------------------------------------------------
local function gifDecode(data, tw, th)
    local sig = data:sub(1, 6)
    if sig ~= "GIF87a" and sig ~= "GIF89a" then return nil, "not a GIF" end
    local flags = data:byte(11)
    local pos = 14
    local gpal
    if flags >= 128 then
        local size = 2 ^ ((flags % 8) + 1)
        gpal = {}
        for i = 0, size - 1 do
            gpal[i] = { data:byte(pos + i * 3), data:byte(pos + i * 3 + 1), data:byte(pos + i * 3 + 2) }
        end
        pos = pos + size * 3
    end
    local transIdx
    while pos <= #data do
        local b = data:byte(pos)
        pos = pos + 1
        if b == 0x21 then
            local label = data:byte(pos)
            pos = pos + 1
            if label == 0xF9 then
                local pk = data:byte(pos + 1)
                if pk % 2 == 1 then transIdx = data:byte(pos + 4) end
            end
            while true do
                local sz = data:byte(pos)
                if not sz then return nil, "GIF is damaged" end
                pos = pos + 1
                if sz == 0 then break end
                pos = pos + sz
            end
        elseif b == 0x2C then
            local fw, fh = u16le(data, pos + 4), u16le(data, pos + 6)
            local fl = data:byte(pos + 8)
            pos = pos + 9
            local pal = gpal
            if fl >= 128 then
                local size = 2 ^ ((fl % 8) + 1)
                pal = {}
                for i = 0, size - 1 do
                    pal[i] = { data:byte(pos + i * 3), data:byte(pos + i * 3 + 1), data:byte(pos + i * 3 + 2) }
                end
                pos = pos + size * 3
            end
            if not pal then return nil, "GIF palette missing" end
            local interlaced = (floor(fl / 64) % 2 == 1)
            local minSize = data:byte(pos)
            pos = pos + 1
            local chunks = {}
            while true do
                local sz = data:byte(pos)
                if not sz then break end
                pos = pos + 1
                if sz == 0 then break end
                chunks[#chunks + 1] = data:sub(pos, pos + sz - 1)
                pos = pos + sz
            end
            local d = table.concat(chunks)
            local sink = newSink(fw, fh, tw, th)
            local put = sink.put
            -- row order
            local rows = {}
            if interlaced then
                for _, p in ipairs({ { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }) do
                    local y = p[1]
                    while y < fh do rows[#rows + 1] = y y = y + p[2] end
                end
            else
                for y = 0, fh - 1 do rows[y + 1] = y end
            end
            local clear = 2 ^ minSize
            local eoi = clear + 1
            local size, nextCode = minSize + 1, clear + 2
            local prefix, suffix = {}, {}
            for i = 0, clear - 1 do prefix[i] = -1 suffix[i] = i end
            local bitbuf, bitcnt, dp = 0, 0, 1
            local prevCode = nil
            local outIdx = 0
            local total = fw * fh
            local stack = {}
            local function emitIndex(v)
                if outIdx >= total then return end
                local y = rows[floor(outIdx / fw) + 1]
                local x = outIdx % fw
                outIdx = outIdx + 1
                if v == transIdx then
                    put(x, y, 0, 0, 0, 0)
                else
                    local c = pal[v] or { 0, 0, 0 }
                    put(x, y, c[1], c[2], c[3], 255)
                end
                if x == fw - 1 then tick() end
            end
            while outIdx < total do
                while bitcnt < size do
                    local b = d:byte(dp)
                    if not b then break end
                    dp = dp + 1
                    bitbuf = bitbuf + b * P2[bitcnt]
                    bitcnt = bitcnt + 8
                end
                if bitcnt < size then break end
                local code = bitbuf % P2[size]
                bitbuf = floor(bitbuf / P2[size])
                bitcnt = bitcnt - size
                if code == clear then
                    size, nextCode, prevCode = minSize + 1, clear + 2, nil
                elseif code == eoi then
                    break
                else
                    local cur = code
                    local first
                    local sp = 0
                    if prevCode ~= nil and code >= nextCode then
                        -- code not in the table yet: previous string + its first char
                        local t = prevCode
                        while prefix[t] ~= -1 do t = prefix[t] end
                        first = suffix[t]
                        cur = prevCode
                        sp = 1
                        stack[1] = first
                    end
                    while prefix[cur] and prefix[cur] ~= -1 do
                        sp = sp + 1
                        stack[sp] = suffix[cur]
                        cur = prefix[cur]
                    end
                    sp = sp + 1
                    stack[sp] = suffix[cur]
                    local firstChar = stack[sp]
                    -- when the special case was used, the extra char sits at stack[1]
                    for i = sp, 1, -1 do emitIndex(stack[i]) end
                    if prevCode ~= nil and nextCode < 4096 then
                        prefix[nextCode] = prevCode
                        suffix[nextCode] = firstChar
                        nextCode = nextCode + 1
                        if nextCode >= P2[size] and size < 12 then size = size + 1 end
                    end
                    prevCode = code
                end
            end
            return sink.finish()
        elseif b == 0x3B then
            break
        end
    end
    return nil, "GIF has no image"
end

-- ------------------------------------------------------------
--  BMP
-- ------------------------------------------------------------
local function bmpDecode(data, tw, th)
    if data:sub(1, 2) ~= "BM" or #data < 54 then return nil, "not a BMP" end
    local offset, dib = u32le(data, 11), u32le(data, 15)
    local w, h = s32le(data, 19), s32le(data, 23)
    local bpp, comp = u16le(data, 29), u32le(data, 31)
    if dib < 40 or w < 1 or h == 0 then return nil, "BMP header not supported" end
    if comp ~= 0 and comp ~= 3 then return nil, "compressed BMP is not supported" end
    local topDown = h < 0
    if topDown then h = -h end
    local stride = floor((w * bpp + 31) / 32) * 4
    if offset + stride * h > #data + 3 then return nil, "BMP pixel data incomplete" end
    local pal = {}
    if bpp <= 8 then
        local colors = u32le(data, 47)
        if colors == 0 then colors = 2 ^ bpp end
        local p = 15 + dib
        for i = 0, colors - 1 do
            pal[i] = { data:byte(p + i * 4 + 2), data:byte(p + i * 4 + 1), data:byte(p + i * 4) }
        end
    end
    local sink = newSink(w, h, tw, th)
    local put = sink.put
    local allZeroAlpha = true
    if bpp == 32 then
        for y = 0, math.min(h, 64) - 1 do
            local row = offset + y * stride
            for x = 0, w - 1, 7 do
                if (data:byte(row + x * 4 + 4) or 0) ~= 0 then allZeroAlpha = false break end
            end
            if not allZeroAlpha then break end
        end
    end
    for y = 0, h - 1 do
        local sy = topDown and y or (h - 1 - y)
        local row = offset + sy * stride + 1
        for x = 0, w - 1 do
            local r, g, b, a = 0, 0, 0, 255
            if bpp == 24 then
                local i = row + x * 3
                b, g, r = data:byte(i, i + 2)
            elseif bpp == 32 then
                local i = row + x * 4
                local aa
                b, g, r, aa = data:byte(i, i + 3)
                if not allZeroAlpha then a = aa end
            elseif bpp == 16 then
                local v = u16le(data, row + x * 2)
                r = floor(floor(v / 1024) % 32 * 255 / 31 + 0.5)
                g = floor(floor(v / 32) % 32 * 255 / 31 + 0.5)
                b = floor(v % 32 * 255 / 31 + 0.5)
            elseif bpp == 8 then
                local c = pal[data:byte(row + x)] or { 0, 0, 0 }
                r, g, b = c[1], c[2], c[3]
            elseif bpp == 4 then
                local byte = data:byte(row + floor(x / 2)) or 0
                local v = (x % 2 == 0) and floor(byte / 16) or byte % 16
                local c = pal[v] or { 0, 0, 0 }
                r, g, b = c[1], c[2], c[3]
            elseif bpp == 1 then
                local byte = data:byte(row + floor(x / 8)) or 0
                local v = floor(byte / P2[7 - x % 8]) % 2
                local c = pal[v] or { 0, 0, 0 }
                r, g, b = c[1], c[2], c[3]
            else
                return nil, "BMP colour depth not supported"
            end
            put(x, y, r or 0, g or 0, b or 0, a)
        end
        if y % 8 == 0 then tick() end
    end
    return sink.finish()
end

-- ------------------------------------------------------------
--  detect + decode
-- ------------------------------------------------------------
-- returns format, width, height   (format "webp"/"html"/"unknown" have no size)
function Dec.probe(data)
    if type(data) ~= "string" or #data < 12 then return "unknown" end
    if data:sub(1, 8) == PNG_SIG then return "png", u32be(data, 17), u32be(data, 21) end
    if data:byte(1) == 0xFF and data:byte(2) == 0xD8 then
        local w, h = jpegProbe(data)
        return "jpeg", w, h
    end
    local s6 = data:sub(1, 6)
    if s6 == "GIF87a" or s6 == "GIF89a" then return "gif", u16le(data, 7), u16le(data, 9) end
    if data:sub(1, 2) == "BM" then
        local h = s32le(data, 23)
        return "bmp", s32le(data, 19), math.abs(h)
    end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "webp" end
    local head = data:sub(1, 64):lower()
    if head:find("<!doctype", 1, true) or head:find("<html", 1, true) or head:sub(1, 1) == "<" then return "html" end
    return "unknown"
end

function Dec.decode(data, tw, th)
    local fmt = Dec.probe(data)
    local ok, a, b
    if fmt == "png" then ok, a, b = pcall(pngDecode, data, tw, th)
    elseif fmt == "jpeg" then ok, a, b = pcall(jpegDecode, data, tw, th)
    elseif fmt == "gif" then ok, a, b = pcall(gifDecode, data, tw, th)
    elseif fmt == "bmp" then ok, a, b = pcall(bmpDecode, data, tw, th)
    else return nil, "unsupported format: " .. fmt, fmt end
    if not ok then return nil, "decoder error: " .. tostring(a), fmt end
    return a, b, fmt
end

return Dec

end)()

-- ============================================================
--  Kraken Galactic Block Art Maker
--  /art  /pos1  /pos2  /artpause  /artresume  /artcancel  /artmap  /artstatus
-- ============================================================
local ART_BLOCK_ID = 10962
local WRENCH_ID = 32
local MAX_BLOCKS = 100000

local ART = {
    url = "", p1 = nil, p2 = nil,
    grid = nil, tw = 0, th = 0, ox = 0, oy = 0, aw = 0, ah = 0,
    fmt = "", srcW = 0, srcH = 0, via = "",
    keep = true, convAuto = true, convAlways = false,
    delay = 150, alpha = 128, serpentine = true, fast = false, stand = "auto",
    modfly = true, autoFind = true, waitFind = false, findBody = nil, flying = false,
    running = false, paused = false, cancel = false, loading = false,
    done = 0, total = 0, skipped = 0, failed = 0, startedAt = 0,
    map = nil, tpl = nil, expect = false, dlgBody = nil, hide = false,
}

local function say(msg)
    if SendVariantList then
        SendVariantList({ [0] = "OnConsoleMessage", [1] = "`b[Art Maker]`o " .. tostring(msg) })
    elseif LogToConsole then
        LogToConsole("[Art Maker] " .. tostring(msg))
    end
end

local function nap(ms)
    if Sleep then Sleep(ms) end
end

local function clamp(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function urlEncode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function field(packet, key)
    return ("\n" .. packet):match("\n" .. key .. "|([^\n]*)")
end

local function splitBar(line)
    local parts = {}
    for piece in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = piece end
    return parts
end

-- ------------------------------------------------------------
--  world access & teleport control
-- ------------------------------------------------------------
local function getPos()
    local p = GetLocal and GetLocal() or nil
    if not p then return nil end
    if p.pos then return math.floor(p.pos.x / 32), math.floor(p.pos.y / 32) end
    if p.pos_x and p.pos_y then return math.floor(p.pos_x / 32), math.floor(p.pos_y / 32) end
    if p.tile_x and p.tile_y then return p.tile_x, p.tile_y end
    return nil
end

local function teleportTo(x, y)
    if SendPacketRaw then
        SendPacketRaw(false, { type = 0, x = x * 32, y = y * 32, state = 0 })
    elseif SendPacket then
        SendPacket(3, string.format("action|walk\nx|%d\ny|%d", x * 32, y * 32))
    end
end

local function fgAt(x, y)
    if GetTile then
        local ok, t = pcall(GetTile, x, y)
        if ok and t then return tonumber(t.fg) or 0 end
    end
    if GetTiles then
        local ok, list = pcall(GetTiles)
        if ok and type(list) == "table" then
            for _, t in pairs(list) do
                if t.x == x and t.y == y then return tonumber(t.fg) or 0 end
            end
        end
    end
    return nil
end

local function invCount(id)
    if not GetInventory then return nil end
    local ok, list = pcall(GetInventory)
    if not ok or type(list) == "table" then return nil end
    for _, it in pairs(list) do
        if it.id == id then return it.amount or it.count or 0 end
    end
    return 0
end

local function canReach(x, y)
    local px, py = getPos()
    if not px then return true end
    return math.abs(px - x) <= 3 and math.abs(py - y) <= 3 and not (px == x and py == y)
end

-- Force teleportation layout to ensure reachability and stay in place or snap back if blocked
local function ensureReach(x, y)
    if canReach(x, y) then return true end
    local tx, ty = x, y + 1
    if ART.stand == "above" then ty = y - 1 end
    teleportTo(tx, ty)
    nap(100)
    if canReach(x, y) then return true end
    
    -- Fallback checks around standard reach zones
    for _, c in ipairs({ { x, y + 1 }, { x, y - 1 }, { x - 1, y }, { x + 1, y } }) do
        local fg = fgAt(c[1], c[2])
        if fg == nil or fg == 0 then
            teleportTo(c[1], c[2])
            nap(100)
            if canReach(x, y) then return true end
        end
    end
    -- Ultimate fallback snap back
    teleportTo(x, y + 1)
    nap(100)
    return canReach(x, y)
end

local function punchTile(item, x, y)
    local me = GetLocal and GetLocal() or nil
    if not me or not me.pos or not SendPacketRaw then return false end
    SendPacketRaw(false, { type = 3, x = me.pos.x, y = me.pos.y, px = x, py = y, value = item, state = 16 })
    return true
end

local function placeAt(x, y)
    if fgAt(x, y) == ART_BLOCK_ID then return true end
    for _ = 1, 3 do
        if not punchTile(ART_BLOCK_ID, x, y) then return false end
        for _ = 1, 10 do
            nap(60)
            local fg = fgAt(x, y)
            if fg == ART_BLOCK_ID then return true end
            if fg == nil then nap(200) return true end
        end
    end
    return false
end

-- ------------------------------------------------------------
--  Kraken colour dialog handling
-- ------------------------------------------------------------
local function parseDialog(body)
    local d = { embed = {}, order = {}, inputs = {}, sliders = {}, checks = {}, buttons = {}, raw = body }
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local p = splitBar(line)
        local cmd = p[1]
        if cmd == "embed_data" and p[2] then
            if d.embed[p[2]] == nil then d.order[#d.order + 1] = p[2] end
            d.embed[p[2]] = p[3] or ""
        elseif cmd == "add_text_input" or cmd == "add_text_input_password" then
            d.inputs[#d.inputs + 1] = { id = p[2], label = p[3] or "", value = p[4] or "" }
        elseif cmd == "add_slider" then
            d.sliders[#d.sliders + 1] = { id = p[2], label = p[3] or "", value = p[4] or "0" }
        elseif cmd == "add_checkbox" then
            d.checks[#d.checks + 1] = { id = p[2], label = p[3] or "", value = p[4] or "0" }
        elseif cmd == "add_button" then
            d.buttons[#d.buttons + 1] = { id = p[2], label = p[3] or "" }
        elseif cmd == "add_button_with_icon" then
            if (p[2] or "") ~= "" or (p[5] or "") ~= "" then
                d.buttons[#d.buttons + 1] = { id = p[2] or "", label = p[3] or "", item = p[5] }
            end
        elseif cmd == "end_dialog" then
            d.name = p[2]
        end
    end
    return d
end

local function stripColors(s)
    return (tostring(s or ""):gsub("`.", ""))
end

local function autoMap(d)
    local map = {}
    local all = {}
    for _, f in ipairs(d.inputs) do all[#all + 1] = f end
    for _, f in ipairs(d.sliders) do all[#all + 1] = f end
    for _, f in ipairs(all) do
        local id = tostring(f.id):lower()
        local key = id .. " " .. stripColors(f.label):lower()
        if not map.r and (key:find("red", 1, true) or id == "r") then map.r = f.id
        elseif not map.g and (key:find("green", 1, true) or id == "g") then map.g = f.id
        elseif not map.b and (key:find("blue", 1, true) or id == "b") then map.b = f.id
        elseif not map.hex and (key:find("hex", 1, true) or key:find("colour", 1, true) or key:find("color", 1, true)) then
            map.hex = f.id
            map.hexHash = tostring(f.value):sub(1, 1) == "#"
        end
    end
    if map.r and map.g and map.b then return map end
    if map.hex then return { hex = map.hex, hexHash = map.hexHash } end
    return nil
end

local function pickButton(d, prefs)
    prefs = prefs or { "save", "apply", "confirm", "accept", "set", "change", "update", "done", "submit", "ok", "paint", "colo" }
    for _, pref in ipairs(prefs) do
        for _, b in ipairs(d.buttons) do
            if (tostring(b.id):lower() .. " " .. stripColors(b.label):lower()):find(pref, 1, true) then return b.id end
        end
    end
    if #d.buttons == 1 then return d.buttons[1].id end
    return nil
end

local function buildReply(d, map, r, g, b, xKey, yKey, x, y)
    local lines = { "action|dialog_return", "dialog_name|" .. tostring(d.name) }
    for _, k in ipairs(d.order) do
        local v = d.embed[k]
        if xKey and k == xKey then v = tostring(x) end
        if yKey and k == yKey then v = tostring(y) end
        lines[#lines + 1] = k .. "|" .. v
    end
    local set = {}
    if map.r then
        set[map.r], set[map.g], set[map.b] = tostring(r), tostring(g), tostring(b)
    elseif map.hex then
        set[map.hex] = (map.hexHash and "#" or "") .. string.format("%02X%02X%02X", r, g, b)
    end
    for _, f in ipairs(d.inputs) do lines[#lines + 1] = f.id .. "|" .. (set[f.id] or f.value) end
    for _, f in ipairs(d.sliders) do lines[#lines + 1] = f.id .. "|" .. (set[f.id] or f.value) end
    for _, f in ipairs(d.checks) do lines[#lines + 1] = f.id .. "|" .. f.value end
    local btn = map.button or pickButton(d)
    if btn then lines[#lines + 1] = "buttonClicked|" .. btn end
    return table.concat(lines, "\n")
end

local function colorBlock(x, y, r, g, b)
    if ART.fast and ART.tpl then
        local t = ART.tpl
        SendPacket(2, buildReply(t.d, t.map, r, g, b, t.xKey, t.yKey, x, y))
        return true
    end
    ART.dlgBody = nil
    ART.expect = true
    ART.hide = true
    punchTile(WRENCH_ID, x, y)
    local body
    for _ = 1, 60 do
        nap(50)
        if ART.dlgBody then body = ART.dlgBody break end
    end
    ART.expect = false
    if not body then return false, "no dialog opened after wrenching" end
    local d = parseDialog(body)
    if not d.name then return false, "dialog had no name" end
    local map = ART.map or autoMap(d)
    if not map then return false, "fields not recognised" end
    SendPacket(2, buildReply(d, map, r, g, b))
    if not ART.tpl then
        local xKey, yKey
        for k, v in pairs(d.embed) do
            if tonumber(v) == x and not xKey and k:lower():find("x", 1, true) then xKey = k end
            if tonumber(v) == y and not yKey and k:lower():find("y", 1, true) then yKey = k end
        end
        ART.tpl = { d = d, map = map, xKey = xKey, yKey = yKey }
    end
    return true
end

local function setModfly(on)
    if ChangeValue then pcall(ChangeValue, "[C] Modfly", on and true or false) end
    ART.flying = on and true or false
end

-- ------------------------------------------------------------
--  item_search Auto-Find restock method[cite: 3]
-- ------------------------------------------------------------
local function restock()
    if not ART.autoFind then return false end
    say("Out of blocks, requesting via item_search...")
    SendPacket(2, "action|dialog_return\ndialog_name|item_search\n" .. ART_BLOCK_ID .. "|1")
    nap(500)
    for _ = 1, 20 do
        local n = invCount(ART_BLOCK_ID)
        if n ~= nil and n > 0 then
            say("Restocked successfully: " .. tostring(n) .. " blocks.")
            return true
        end
        nap(100)
    end
    return false
end

-- ------------------------------------------------------------
--  Image Processing / Loading
-- ------------------------------------------------------------
local function extractBody(a, b)
    if type(a) == "string" then return a end
    if type(a) == "table" then
        local code = tonumber(a.status or a.code or a.status_code)
        if code and code >= 400 then return nil end
        for _, k in ipairs({ "content", "body", "data", "response", "text", "result" }) do
            if type(a[k]) == "string" and #a[k] > 0 then return a[k] end
        end
    end
    if type(b) == "string" then return b end
    return nil
end

local function httpGet(url)
    if not url:match("^https?://") then
        if not (io and io.open) then return nil, "file access not available" end
        local f = io.open(url, "rb")
        if not f then return nil, "file not found: " .. url end
        local d = f:read("*all")
        f:close()
        return d
    end
    if type(MakeRequest) ~= "function" then return nil, "MakeRequest() unavailable" end
    for _, fn in ipairs({
        function() return MakeRequest(url, "GET", { ["User-Agent"] = "Mozilla/5.0", ["Accept"] = "image/*,*/*" }) end,
        function() return MakeRequest(url, "GET") end,
        function() return MakeRequest(url) end,
    }) do
        local ok, a, b = pcall(fn)
        if ok then
            local body = extractBody(a, b)
            if type(body) == "string" and #body > 0 then return body end
        end
    end
    return nil, "failed to fetch url"
end

local function fitSize(sw, sh, aw, ah, keep)
    if not keep then return aw, ah end
    local s = math.min(aw / sw, ah / sh)
    return math.max(1, math.min(aw, math.floor(sw * s + 0.5))), math.max(1, math.min(ah, math.floor(sh * s + 0.5)))
end

local function tryDecode(body)
    local fmt, sw, sh = Dec.probe(body)
    if fmt == "html" then return nil, "link is a web page" end
    if not sw or not sh or sw < 1 or sh < 1 then return nil, "needs online converter", fmt end
    local tw, th = fitSize(sw, sh, ART.aw, ART.ah, ART.keep)
    local grid, err = Dec.decode(body, tw, th)
    if not grid then return nil, err, fmt, sw, sh end
    return grid, nil, fmt, sw, sh
end

local function loadImage()
    local errors = {}
    local grid, fmt, sw, sh, via
    if not ART.convAlways then
        local body, err = httpGet(ART.url)
        if body then
            local g, e, f, w, h = tryDecode(body)
            if g then grid, fmt, sw, sh, via = g, f, w, h, "direct" else errors[#errors + 1] = tostring(e) end
        else
            errors[#errors + 1] = tostring(err)
        end
    end
    if not grid and (ART.convAuto or ART.convAlways) and ART.url:match("^https?://") then
        say("Trying online converter...")
        local cu = "https://wsrv.nl/?url=" .. urlEncode(ART.url) .. "&w=" .. ART.aw .. "&h=" .. ART.ah
            .. "&fit=" .. (ART.keep and "inside" or "fill") .. "&output=png"
        local body, err = httpGet(cu)
        if body then
            local g, e, f, w, h = tryDecode(body)
            if g then grid, fmt, sw, sh, via = g, "converted", w, h, "converter"
            else errors[#errors + 1] = "converter: " .. tostring(e) end
        else
            errors[#errors + 1] = "converter: " .. tostring(err)
        end
    end
    if not grid then
        say("`4Could not load image.")
        for _, e in ipairs(errors) do say("  - " .. e) end
        return false
    end
    ART.grid, ART.fmt, ART.srcW, ART.srcH, ART.via = grid, fmt, sw, sh, via
    ART.tw, ART.th = grid.w, grid.h
    ART.ox = math.floor((ART.aw - ART.tw) / 2)
    ART.oy = math.floor((ART.ah - ART.th) / 2)
    ART.total, ART.done, ART.skipped, ART.failed = ART.tw * ART.th, 0, 0, 0
    say(string.format("Image ready (%s, %s): %d x %d blocks.", tostring(fmt), via, ART.tw, ART.th))
    return true
end

local function areaOf()
    if not ART.p1 or not ART.p2 then return nil end
    local minX, maxX = math.min(ART.p1.x, ART.p2.x), math.max(ART.p1.x, ART.p2.x)
    local minY, maxY = math.min(ART.p1.y, ART.p2.y), math.max(ART.p1.y, ART.p2.y)
    return minX, minY, maxX - minX + 1, maxY - minY + 1
end

local function prepareImage()
    if ART.loading then say("Already loading an image.") return end
    if ART.url == "" then say("Paste an image link first.") return end
    local _, _, aw, ah = areaOf()
    if not aw then say("Set corners using /pos1 and /pos2.") return end
    if aw * ah > MAX_BLOCKS then say("Area exceeds max block limit.") return end
    ART.aw, ART.ah = aw, ah
    ART.loading = true
    ART.grid = nil
    say("Loading image...")
    RunThread(function()
        Dec.yield = function() nap(1) end
        local ok, err = pcall(loadImage)
        ART.loading = false
        if not ok then say("`4Image load crashed: " .. tostring(err)) end
    end)
end

-- ------------------------------------------------------------
--  Building Thread Routine
-- ------------------------------------------------------------
local function timeLeft()
    if ART.done <= 0 then return "?" end
    local spent = os.time() - ART.startedAt
    local left = math.floor(spent / ART.done * (ART.total - ART.done - ART.skipped))
    if left < 0 then left = 0 end
    return string.format("%dm %02ds", math.floor(left / 60), left % 60)
end

local function waitWhilePaused()
    while ART.paused and not ART.cancel do nap(200) end
    return not ART.cancel
end

local function build()
    if ART.running then say("A build is already running.") return end
    if not ART.grid then say("Load the image first.") return end
    local minX, minY = areaOf()
    if not minX then say("Set both corners first.") return end
    ART.running, ART.paused, ART.cancel = true, false, false
    ART.tpl = nil
    ART.done, ART.skipped, ART.failed = 0, 0, 0
    ART.startedAt = os.time()
    ART.hide = true
    if ART.modfly then setModfly(true) end
    local grid = ART.grid
    local tw, th = ART.tw, ART.th

    RunThread(function()
        local fails = 0
        local ok, err = pcall(function()
            for cy = 0, th - 1 do
                local from, to, step = 0, tw - 1, 1
                if ART.serpentine and cy % 2 == 1 then from, to, step = tw - 1, 0, -1 end
                for cx = from, to, step do
                    if not waitWhilePaused() then return end
                    local i = cy * tw + cx + 1
                    if (grid.a[i] or 255) < ART.alpha then
                        ART.skipped = ART.skipped + 1
                    else
                        local x, y = minX + ART.ox + cx, minY + ART.oy + cy
                        local have = invCount(ART_BLOCK_ID)
                        
                        while have ~= nil and have <= 0 and not ART.cancel do
                            local got = false
                            if ART.autoFind then got = restock() end
                            if not got then
                                ART.skipped = ART.skipped + 1
                                break
                            end
                            have = invCount(ART_BLOCK_ID)
                        end
                        if ART.cancel then return end
                        if (invCount(ART_BLOCK_ID) or 0) <= 0 then
                            goto continue_block
                        end

                        local done = false
                        if ensureReach(x, y) and placeAt(x, y) then
                            local c, why = colorBlock(x, y, grid.r[i], grid.g[i], grid.b[i])
                            if c then
                                done = true
                            elseif why then
                                ART.failed = ART.failed + 1
                                nap(ART.delay)
                                goto continue_block
                            end
                        end
                        if done then
                            fails = 0
                            ART.done = ART.done + 1
                        else
                            fails = fails + 1
                            ART.failed = ART.failed + 1
                            if fails >= 25 then fails = 0 end
                        end
                        if (ART.done + ART.failed) % 25 == 0 then
                            say(string.format("Progress %d/%d (%d%%) Left: %s", ART.done, ART.total - ART.skipped,
                                math.floor(ART.done * 100 / math.max(1, ART.total - ART.skipped)), timeLeft()))
                        end
                        nap(ART.delay)
                        ::continue_block::
                    end
                end
            end
        end)
        ART.running = false
        ART.hide = false
        if ART.flying then setModfly(false) end
        if not ok then say("`4Build crashed: " .. tostring(err)) end
        if ART.cancel then say("Build cancelled.")
        elseif ok then say(string.format("Build finished: %d placed, %d skipped, %d failed.", ART.done, ART.skipped, ART.failed)) end
    end)
end

local function testBlock()
    local minX, minY = areaOf()
    if not minX then say("Set both corners first.") return end
    if ART.running then say("A build is running.") return end
    ART.hide = true
    RunThread(function()
        local x, y = minX, minY
        local r, g, b = 255, 0, 0
        if ART.grid then r, g, b = ART.grid.r[1], ART.grid.g[1], ART.grid.b[1] end
        local ok = ensureReach(x, y) and placeAt(x, y)
        if not ok then say("`4Could not place test block.") ART.hide = false return end
        local c, why = colorBlock(x, y, r, g, b)
        ART.hide = false
        if c then say("Test block colored successfully!") else say("`4Test failed: " .. tostring(why)) end
    end)
end

-- ------------------------------------------------------------
--  Reworked Clean & Readable Menu
-- ------------------------------------------------------------
local function statusLine()
    local a = "Not Set"
    local minX, minY, aw, ah = areaOf()
    if minX then a = aw .. "x" .. ah .. " blocks" end
    local img = ART.grid and (ART.tw .. "x" .. ART.th .. " Ready") or "No Image"
    local run = ART.running and (ART.paused and "Paused" or "Building...") or "Idle"
    return string.format("Area: %s | Image: %s | Status: %s", a, img, run)
end

local function openArtMenu()
    local function chk(id, label, on) return "add_checkbox|" .. id .. "|" .. label .. "|" .. (on and "1" or "0") .. "|\n" end
    local body = "set_default_color|`o\n"
        .. "add_label_with_icon|big|`wKraken Galactic Art Maker|left|" .. ART_BLOCK_ID .. "|\n"
        .. "add_smalltext|" .. statusLine() .. "|\n"
        .. "add_spacer|small|\n"
        .. "add_textbox|--- `9IMAGE SETUP `o---|\n"
        .. "add_text_input|art_url|Image Link:|" .. ART.url .. "|250|\n"
        .. "add_smalltext|Stand on corner 1 and type `/pos1`, then corner 2 and type `/pos2`.|\n"
        .. "add_spacer|small|\n"
        .. "add_textbox|--- `9BUILD CONFIGURATION `o---|\n"
        .. chk("art_keep", "Keep Picture Proportions", ART.keep)
        .. chk("art_conv", "Auto-use Online Converter (WebP/Huge files)", ART.convAuto)
        .. chk("art_convall", "Always use Online Converter", ART.convAlways)
        .. chk("art_serp", "Serpentine Order (Less Walking)", ART.serpentine)
        .. chk("art_fast", "Fast Mode (Experimental Wrench Skip)", ART.fast)
        .. chk("art_fly", "Enable Modfly During Build", ART.modfly)
        .. chk("art_find", "Auto-Find Restock (via item_search)", ART.autoFind)
        .. "add_text_input|art_delay|Delay Between Blocks (ms):|" .. ART.delay .. "|5|\n"
        .. "add_text_input|art_alpha|Transparency Skip Threshold (0-255):|" .. ART.alpha .. "|3|\n"
        .. "add_text_input|art_stand|Stand Position (auto / below / above):|" .. ART.stand .. "|6|\n"
        .. "add_spacer|small|\n"
        .. "add_textbox|--- `9CONTROLS `o---|\n"
        .. "add_button|art_load|Download & Prepare Image|noflags|0|0|\n"
        .. "add_button|art_test|Test Single Block (Corner 1)|noflags|0|0|\n"
        .. "add_button|art_start|Start Building|noflags|0|0|\n"
        .. "add_button|art_pause|Pause Build|noflags|0|0|\n"
        .. "add_button|art_resume|Resume Build|noflags|0|0|\n"
        .. "add_button|art_cancel|Cancel Build|noflags|0|0|\n"
        .. "end_dialog|kraken_art_menu|Close|Save Settings|\n"
    SendVariantList({ [0] = "OnDialogRequest", [1] = body })
end

local function readMenu(packet)
    local url = field(packet, "art_url")
    if url == nil then return end
    ART.url = url:gsub("^%s+", ""):gsub("%s+$", "")
    ART.keep = field(packet, "art_keep") == "1"
    ART.convAuto = field(packet, "art_conv") == "1"
    ART.convAlways = field(packet, "art_convall") == "1"
    ART.serpentine = field(packet, "art_serp") == "1"
    ART.fast = field(packet, "art_fast") == "1"
    ART.modfly = field(packet, "art_fly") == "1"
    ART.autoFind = field(packet, "art_find") == "1"
    ART.delay = clamp(field(packet, "art_delay"), 0, 5000)
    ART.alpha = clamp(field(packet, "art_alpha"), 0, 255)
    local st = (field(packet, "art_stand") or "auto"):lower()
    if st == "below" or st == "above" then ART.stand = st else ART.stand = "auto" end
end

-- ------------------------------------------------------------
--  Command & Hook Handlers
-- ------------------------------------------------------------
AddHook("onvariant", "KRAKEN_ART_DIALOG", function(v)
    if not v or v[0] ~= "OnDialogRequest" or type(v[1]) ~= "string" then return false end
    if ART.expect then
        ART.dlgBody = v[1]
        ART.expect = false
        return true
    end
    if ART.hide and (ART.running or ART.tpl == nil) then return true end
    return false
end)

AddHook("onsendpacket", "KRAKEN_ART_COMMANDS", function(packetType, packet)
    if type(packet) ~= "string" then return false end
    local msg = packet:match("action|input\n|text|([^\n]*)")
    if not msg then return false end
    msg = msg:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = msg:lower()
    if low == "/art" then openArtMenu() return true end
    if low == "/pos1" or low == "/pos2" then
        local x, y = getPos()
        if x then
            if low == "/pos1" then ART.p1 = { x = x, y = y } else ART.p2 = { x = x, y = y } end
            say("Position " .. low:sub(5) .. " set: " .. x .. ", " .. y)
        else
            say("Could not read your position.")
        end
        return true
    end
    if low == "/artpause" then ART.paused = true say("Paused.") return true end
    if low == "/artresume" then ART.paused = false say("Resumed.") return true end
    if low == "/artcancel" then ART.cancel = true ART.paused = false say("Cancel requested.") return true end
    if low == "/artstatus" then say(statusLine()) return true end
    return false
end)

AddHook("onsendpacket", "KRAKEN_ART_MENU_ACTIONS", function(packetType, packet)
    if type(packet) ~= "string" or not packet:find("dialog_name|kraken_art_menu", 1, true) then return false end
    readMenu(packet)
    local btn = field(packet, "buttonClicked") or ""
    if btn == "art_load" then prepareImage()
    elseif btn == "art_test" then testBlock()
    elseif btn == "art_start" then build()
    elseif btn == "art_pause" then ART.paused = true say("Paused.")
    elseif btn == "art_resume" then ART.paused = false say("Resumed.")
    elseif btn == "art_cancel" then ART.cancel = true ART.paused = false say("Cancel requested.") end
    return true
end)

say("Loaded cleanly. Type /art to open configuration menu.")