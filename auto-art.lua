-- Kraken Galactic Block Art Maker  (block 10962)
-- Menu: /art      Pause / resume / cancel: /artpause /artresume /artcancel
-- GitHub: set your name + repository in the LOCK line below, put the user ids in uids.txt in that repository.
-- Reads PNG, JPG (baseline), GIF and BMP itself; anything else goes through the online converter.

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
--  shrinking  -> exact area average (box filter), every source pixel counts by how much it overlaps
--  enlarging  -> bilinear (smooth) or nearest (Dec.smooth = false)
-- ------------------------------------------------------------
Dec.smooth = true
Dec.linear = true        -- average colours in linear light (keeps brightness right)

local TOLIN = {}
for i = 0, 255 do
    local c = i / 255
    TOLIN[i] = (c <= 0.04045) and (c / 12.92) or (((c + 0.055) / 1.055) ^ 2.4)
end
local function fromLin(v)
    if v <= 0 then return 0 end
    if v >= 1 then return 255 end
    local c = (v <= 0.0031308) and (v * 12.92) or (1.055 * v ^ (1 / 2.4) - 0.055)
    return floor(c * 255 + 0.5)
end

local function axisMap(sw, tw)
    local map = {}
    local scale = tw / sw
    for px = 0, sw - 1 do
        local a, b = px * scale, (px + 1) * scale
        local t0, t1 = floor(a), math.ceil(b) - 1
        if t1 >= tw then t1 = tw - 1 end
        local list = {}
        for t = t0, t1 do
            local lo = (a > t) and a or t
            local hi = (b < t + 1) and b or (t + 1)
            local w = hi - lo
            if w > 1e-9 then list[#list + 1] = { t, w } end
        end
        map[px] = list
    end
    return map
end

local function newSink(sw, sh, tw, th)
    local S = { sw = sw, sh = sh, tw = tw, th = th }
    local enlarge = (sw <= tw and sh <= th)
    if enlarge then
        local pix = {}
        S.put = function(px, py, r, g, b, a)
            pix[py * sw + px + 1] = ((a * 256 + r) * 256 + g) * 256 + b
        end
        local function unpack4(v)
            if not v then return 0, 0, 0, 0 end
            local b = v % 256; v = floor(v / 256)
            local g = v % 256; v = floor(v / 256)
            local r = v % 256; v = floor(v / 256)
            return r, g, b, v
        end
        S.finish = function()
            local out = { w = tw, h = th, r = {}, g = {}, b = {}, a = {} }
            local smooth = Dec.smooth and (sw > 1 or sh > 1)
            local lin = Dec.linear
            for ty = 0, th - 1 do
                local sy = (ty + 0.5) * sh / th - 0.5
                if sy < 0 then sy = 0 elseif sy > sh - 1 then sy = sh - 1 end
                local y0 = floor(sy)
                local y1 = (y0 + 1 < sh) and (y0 + 1) or y0
                local fy = sy - y0
                for tx = 0, tw - 1 do
                    local sx = (tx + 0.5) * sw / tw - 0.5
                    if sx < 0 then sx = 0 elseif sx > sw - 1 then sx = sw - 1 end
                    local x0 = floor(sx)
                    local i = ty * tw + tx + 1
                    if not smooth then
                        local r, g, b, a = unpack4(pix[floor(ty * sh / th) * sw + floor(tx * sw / tw) + 1])
                        out.r[i], out.g[i], out.b[i], out.a[i] = r, g, b, a
                    else
                        local x1 = (x0 + 1 < sw) and (x0 + 1) or x0
                        local fx = sx - x0
                        local r00, g00, b00, a00 = unpack4(pix[y0 * sw + x0 + 1])
                        local r10, g10, b10, a10 = unpack4(pix[y0 * sw + x1 + 1])
                        local r01, g01, b01, a01 = unpack4(pix[y1 * sw + x0 + 1])
                        local r11, g11, b11, a11 = unpack4(pix[y1 * sw + x1 + 1])
                        if lin then
                            r00, g00, b00 = TOLIN[r00], TOLIN[g00], TOLIN[b00]
                            r10, g10, b10 = TOLIN[r10], TOLIN[g10], TOLIN[b10]
                            r01, g01, b01 = TOLIN[r01], TOLIN[g01], TOLIN[b01]
                            r11, g11, b11 = TOLIN[r11], TOLIN[g11], TOLIN[b11]
                        end
                        local w00, w10, w01, w11 = (1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy
                        local wa00, wa10, wa01, wa11 = w00 * a00, w10 * a10, w01 * a01, w11 * a11
                        local asum = wa00 + wa10 + wa01 + wa11
                        if asum > 0 then
                            local rr = (r00 * wa00 + r10 * wa10 + r01 * wa01 + r11 * wa11) / asum
                            local gg = (g00 * wa00 + g10 * wa10 + g01 * wa01 + g11 * wa11) / asum
                            local bb = (b00 * wa00 + b10 * wa10 + b01 * wa01 + b11 * wa11) / asum
                            if lin then
                                out.r[i], out.g[i], out.b[i] = fromLin(rr), fromLin(gg), fromLin(bb)
                            else
                                out.r[i], out.g[i], out.b[i] = floor(rr + 0.5), floor(gg + 0.5), floor(bb + 0.5)
                            end
                        else
                            out.r[i], out.g[i], out.b[i] = 0, 0, 0
                        end
                        out.a[i] = floor(w00 * a00 + w10 * a10 + w01 * a01 + w11 * a11 + 0.5)
                    end
                end
            end
            return out
        end
    else
        local xm, ym = axisMap(sw, tw), axisMap(sh, th)
        local n = tw * th
        local sr, sg, sb, sa = {}, {}, {}, {}
        for i = 1, n do sr[i], sg[i], sb[i], sa[i] = 0, 0, 0, 0 end
        local lin = Dec.linear
        S.put = function(px, py, r, g, b, a)
            if lin then r, g, b = TOLIN[r], TOLIN[g], TOLIN[b] end
            local xl, yl = xm[px], ym[py]
            for yi = 1, #yl do
                local ty, wy = yl[yi][1], yl[yi][2]
                local base = ty * tw + 1
                for xi = 1, #xl do
                    local e = xl[xi]
                    local i = base + e[1]
                    local wa = e[2] * wy * a
                    sr[i] = sr[i] + r * wa
                    sg[i] = sg[i] + g * wa
                    sb[i] = sb[i] + b * wa
                    sa[i] = sa[i] + wa
                end
            end
        end
        S.finish = function()
            local out = { w = tw, h = th, r = {}, g = {}, b = {}, a = {} }
            for i = 1, n do
                local a = sa[i]
                if a > 0 then
                    if lin then
                        out.r[i], out.g[i], out.b[i] = fromLin(sr[i] / a), fromLin(sg[i] / a), fromLin(sb[i] / a)
                    else
                        out.r[i] = floor(sr[i] / a + 0.5)
                        out.g[i] = floor(sg[i] / a + 0.5)
                        out.b[i] = floor(sb[i] / a + 0.5)
                    end
                    out.a[i] = floor(a + 0.5)
                else
                    out.r[i], out.g[i], out.b[i], out.a[i] = 0, 0, 0, 0
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
--  /art  /artpause  /artresume  /artcancel  /artstatus  /artmap
-- ============================================================
local ART_BLOCK_ID = 10962
local WRENCH_ID = 32
local ALPHA_MIN = 128
local MAX_BLOCKS = 250000                   -- only a safety net against typing a huge size by mistake

local ART = {
    url = "", mid = nil, sizeW = 50, sizeH = 50, p1 = nil, p2 = nil, areaMode = "mid",
    keep = true, sharpen = 30, modfly = true, autoFind = true, refillTo = 100,
    t = { blockGap = 100, placeWait = 60, retryWait = 350, dialogWait = 3000, hopShort = 130, hopLong = 260,
          shortDist = 8, refillWait = 100, refillTimeout = 25 },
    grid = nil, tw = 0, th = 0, ox = 0, oy = 0, aw = 0, ah = 0, sig = "", fmt = "", srcW = 0, srcH = 0, via = "",
    running = false, paused = false, cancel = false, loading = false,
    order = nil, cursor = 1, done = 0, total = 0, startedAt = 0, activeTime = 0, lastTickTime = 0,
    map = nil, expect = false, dlgBody = nil, hide = false,
    flying = false,
}

-- ------------------------------------------------------------
--  persistent session checkpoint
-- ------------------------------------------------------------
local SESSION_FILE = "auto_art_session.dat"
local resumePending = false

local function encodeValue(v, seen)
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" or t == "number" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return "nil" end
    seen = seen or {}
    if seen[v] then return "nil" end
    seen[v] = true
    local out = {"{"}
    for k, value in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            out[#out + 1] = "[" .. encodeValue(k, seen) .. "]=" .. encodeValue(value, seen) .. ","
        end
    end
    out[#out + 1] = "}"
    seen[v] = nil
    return table.concat(out)
end

local function sessionSnapshot()
    return {
        version = 1,
        url = ART.url, mid = ART.mid, sizeW = ART.sizeW, sizeH = ART.sizeH,
        p1 = ART.p1, p2 = ART.p2, areaMode = ART.areaMode,
        keep = ART.keep, sharpen = ART.sharpen, modfly = ART.modfly,
        autoFind = ART.autoFind, refillTo = ART.refillTo, t = ART.t,
        grid = ART.grid, tw = ART.tw, th = ART.th, ox = ART.ox, oy = ART.oy,
        aw = ART.aw, ah = ART.ah, sig = ART.sig, fmt = ART.fmt,
        srcW = ART.srcW, srcH = ART.srcH, via = ART.via, map = ART.map,
        cursor = ART.cursor, done = ART.done, total = ART.total,
        savedAt = os.time()
    }
end

local function saveSession()
    if not (io and io.open) then return false end
    local ok, data = pcall(encodeValue, sessionSnapshot())
    if not ok or type(data) ~= "string" then return false end
    local f = io.open(SESSION_FILE, "w")
    if not f then return false end
    local wrote = pcall(function() f:write(data) f:flush() end)
    f:close()
    return wrote
end

local function loadSession()
    if not (io and io.open) then return false end
    local f = io.open(SESSION_FILE, "r")
    if not f then return false end
    local data = f:read("*all")
    f:close()
    if type(data) ~= "string" or data == "" then return false end
    -- The file is generated by this script; still validate the returned structure.
    local compiler = loadstring or load
    if type(compiler) ~= "function" then return false end
    local chunk = compiler("return " .. data)
    if not chunk then return false end
    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" or saved.version ~= 1 then return false end
    ART.url = tostring(saved.url or "")
    ART.mid = type(saved.mid) == "table" and saved.mid or nil
    ART.p1 = type(saved.p1) == "table" and saved.p1 or nil
    ART.p2 = type(saved.p2) == "table" and saved.p2 or nil
    ART.areaMode = (saved.areaMode == "corners") and "corners" or "mid"
    for _, k in ipairs({"sizeW", "sizeH", "sharpen", "refillTo", "tw", "th", "ox", "oy", "aw", "ah", "srcW", "srcH", "cursor", "done", "total"}) do
        if tonumber(saved[k]) then ART[k] = tonumber(saved[k]) end
    end
    for _, k in ipairs({"keep", "modfly", "autoFind"}) do
        if type(saved[k]) == "boolean" then ART[k] = saved[k] end
    end
    if type(saved.t) == "table" then ART.t = saved.t end
    if type(saved.grid) == "table" and tonumber(saved.grid.w) and tonumber(saved.grid.h)
        and type(saved.grid.r) == "table" and type(saved.grid.g) == "table"
        and type(saved.grid.b) == "table" and type(saved.grid.a) == "table" then
        ART.grid = saved.grid
    end
    ART.sig = tostring(saved.sig or "")
    ART.fmt, ART.via = tostring(saved.fmt or ""), tostring(saved.via or "")
    ART.map = type(saved.map) == "table" and saved.map or nil
    resumePending = ART.grid ~= nil and ART.cursor > 1 and ART.cursor <= (ART.total > 0 and ART.total or math.huge)
    ART.running, ART.paused, ART.cancel, ART.loading = false, true, false, false
    return true
end

local function say(msg)
    if SendVariantList then
        SendVariantList({ [0] = "OnConsoleMessage", [1] = "`2[Art]`o " .. tostring(msg) })
    elseif LogToConsole then
        LogToConsole("[Art] " .. tostring(msg))
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

local function round(v) return math.floor(v + 0.5) end

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

-- whatever got pasted: keep only the link itself
local function cleanUrl(s)
    s = tostring(s or ""):gsub("\194\160", " "):gsub("%c", " ")
    local at = s:find("https?://")
    if at then
        s = s:sub(at):match("^(%S+)") or ""
    else
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
    end
    s = s:gsub("^[\"'<%(]+", ""):gsub("[\"'>%)]+$", "")
    return s
end

local function parseSize(text)
    text = tostring(text or "")
    local w, h = text:match("(%d+)%s*[xX%*]%s*(%d+)")
    if not w then
        w = text:match("(%d+)")
        h = w
    end
    w, h = tonumber(w), tonumber(h)
    if not w or not h or w < 1 or h < 1 then return nil end
    return w, h
end

-- ------------------------------------------------------------
--  world access
-- ------------------------------------------------------------
local function getPos()
    local p = GetLocal and GetLocal() or nil
    if not p then return nil end
    if p.pos then return math.floor(p.pos.x / 32), math.floor(p.pos.y / 32) end
    if p.pos_x and p.pos_y then return math.floor(p.pos_x / 32), math.floor(p.pos_y / 32) end
    if p.tile_x and p.tile_y then return p.tile_x, p.tile_y end
    return nil
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
    if not ok or type(list) ~= "table" then return nil end
    for _, it in pairs(list) do
        if it.id == id then return it.amount or it.count or 0 end
    end
    return 0
end

local function walkTo(x, y)
    local cx, cy = getPos()
    if not cx then
        if FindPath then FindPath(x, y) end
        nap(300)
        return
    end
    if cx == x and cy == y then return end
    local total = math.max(math.abs(x - cx), math.abs(y - cy))
    local gap = (total <= ART.t.shortDist) and ART.t.hopShort or ART.t.hopLong
    if not FindPath then
        SendPacket(3, string.format("action|walk\nx|%d\ny|%d", x * 32, y * 32))
        nap(gap)
        return
    end
    for _ = 1, 80 do
        local dx, dy = x - cx, y - cy
        local dist = math.max(math.abs(dx), math.abs(dy))
        if dist == 0 then return end
        if dist <= 4 then
            FindPath(x, y)
            nap(gap)
            return
        end
        local f = 4 / dist
        FindPath(cx + round(dx * f), cy + round(dy * f))
        nap(gap)
        local mx, my = getPos()
        if not mx or (mx == cx and my == cy) then
            nap(gap)
            mx, my = getPos()
            if not mx or (mx == cx and my == cy) then return end
        end
        cx, cy = mx, my
    end
end

local function canReach(x, y)
    local px, py = getPos()
    if not px then return true end
    return math.abs(px - x) <= 3 and math.abs(py - y) <= 3 and not (px == x and py == y)
end

local function ensureReach(x, y, dir)
    if canReach(x, y) then return true end
    dir = dir or 1
    local cands = {
        { x + 3 * dir, y + 1 }, { x + 3 * dir, y - 1 }, { x, y + 1 }, { x, y - 1 },
        { x - dir, y + 1 }, { x - dir, y - 1 }, { x + dir, y }, { x - dir, y },
    }
    for _, c in ipairs(cands) do
        local sx, sy = c[1], c[2]
        if sx >= 0 and sy >= 0 and not (sx == x and sy == y) then
            local fg = fgAt(sx, sy)
            if fg == nil or fg == 0 then
                walkTo(sx, sy)
                if canReach(x, y) then return true end
            end
        end
    end
    return false
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
            nap(ART.t.placeWait)
            local fg = fgAt(x, y)
            if fg == ART_BLOCK_ID then return true end
            if fg == nil then nap(200) return true end
        end
    end
    return false
end

-- ------------------------------------------------------------
--  Kraken colour dialog
-- ------------------------------------------------------------
local function stripColors(s)
    return (tostring(s or ""):gsub("`.", ""))
end

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

local function genericReply(d, set, btn)
    local lines = { "action|dialog_return", "dialog_name|" .. tostring(d.name) }
    for _, k in ipairs(d.order) do lines[#lines + 1] = k .. "|" .. d.embed[k] end
    for _, f in ipairs(d.inputs) do lines[#lines + 1] = f.id .. "|" .. (set[f.id] or f.value) end
    for _, f in ipairs(d.sliders) do lines[#lines + 1] = f.id .. "|" .. (set[f.id] or f.value) end
    for _, f in ipairs(d.checks) do lines[#lines + 1] = f.id .. "|" .. f.value end
    if btn then lines[#lines + 1] = "buttonClicked|" .. tostring(btn) end
    return table.concat(lines, "\n")
end

local function colorReply(d, map, r, g, b)
    local set = {}
    if map.r then
        set[map.r], set[map.g], set[map.b] = tostring(r), tostring(g), tostring(b)
    elseif map.hex then
        set[map.hex] = (map.hexHash and "#" or "") .. string.format("%02X%02X%02X", r, g, b)
    end
    return genericReply(d, set, map.button or pickButton(d))
end

local function colorBlock(x, y, r, g, b)
    ART.dlgBody = nil
    ART.expect = true
    ART.hide = true
    punchTile(WRENCH_ID, x, y)
    local body
    local waited = 0
    while waited < ART.t.dialogWait do
        nap(50)
        waited = waited + 50
        if ART.dlgBody then body = ART.dlgBody break end
    end
    ART.expect = false
    if not body then return false, "no dialog", true end
    local d = parseDialog(body)
    if not d.name then return false, "no name", true end
    local map = ART.map or autoMap(d)
    if not map then return false, "bad fields", true end
    if not map.r and not map.hex then return false, "bad map", true end
    SendPacket(2, colorReply(d, map, r, g, b))
    return true
end

-- ------------------------------------------------------------
--  modfly
-- ------------------------------------------------------------
local function setModfly(on)
    if ChangeValue then pcall(ChangeValue, "[C] Modfly", on and true or false) end
    ART.flying = on and true or false
end

-- ------------------------------------------------------------
--  out of blocks: ask the server's item search for more
-- ------------------------------------------------------------
local function restock()
    local target = ART.refillTo
    say("Refilling (" .. target .. ")...")
    local started = os.time()
    local last = invCount(ART_BLOCK_ID) or 0
    local idle = 0
    while true do
        if ART.cancel then return false end
        local have = invCount(ART_BLOCK_ID)
        if have == nil or have >= target then return true end
        if os.time() - started >= ART.t.refillTimeout then break end
        SendPacket(2, "action|dialog_return\ndialog_name|item_search\n" .. ART_BLOCK_ID .. "|1")
        nap(ART.t.refillWait)
        local now = invCount(ART_BLOCK_ID) or 0
        if now > last then last = now idle = 0 else idle = idle + 1 end
        if idle >= 40 then break end
    end
    return (invCount(ART_BLOCK_ID) or 0) > 0
end

-- ------------------------------------------------------------
--  getting the picture
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
        if not (io and io.open) then return nil, "file error" end
        local f = io.open(url, "rb")
        if not f then return nil, "not found" end
        local d = f:read("*all")
        f:close()
        return d
    end
    if type(MakeRequest) ~= "function" then return nil, "no request" end
    local attempts = {
        function() return MakeRequest(url, "GET", { ["User-Agent"] = "Mozilla/5.0", ["Accept"] = "image/*,*/*" }) end,
        function() return MakeRequest(url, "GET") end,
        function() return MakeRequest(url) end,
    }
    for _, fn in ipairs(attempts) do
        local ok, a, b = pcall(fn)
        if ok then
            local body = extractBody(a, b)
            if type(body) == "string" and #body > 0 then return body end
        end
    end
    return nil, "failed"
end

local function fitSize(sw, sh, aw, ah, keep)
    if not keep then return aw, ah end
    local s = math.min(aw / sw, ah / sh)
    return math.max(1, math.min(aw, round(sw * s))), math.max(1, math.min(ah, round(sh * s)))
end

local function sharpenGrid(grid, amount)
    if amount <= 0 then return end
    local w, h = grid.w, grid.h
    local k = amount / 100
    local nr, ng, nb = {}, {}, {}
    local function c(v) v = round(v) if v < 0 then return 0 elseif v > 255 then return 255 end return v end
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local i = y * w + x + 1
            local sr, sg, sb, cnt = 0, 0, 0, 0
            for dy = -1, 1 do
                local yy = y + dy
                if yy >= 0 and yy < h then
                    for dx = -1, 1 do
                        local xx = x + dx
                        if xx >= 0 and xx < w then
                            local j = yy * w + xx + 1
                            sr, sg, sb, cnt = sr + grid.r[j], sg + grid.g[j], sb + grid.b[j], cnt + 1
                        end
                    end
                end
            end
            local r, g, b = grid.r[i], grid.g[i], grid.b[i]
            nr[i], ng[i], nb[i] = c(r + k * (r - sr / cnt)), c(g + k * (g - sg / cnt)), c(b + k * (b - sb / cnt))
        end
    end
    grid.r, grid.g, grid.b = nr, ng, nb
end

local function tryDecode(body)
    local fmt, sw, sh = Dec.probe(body)
    if fmt == "html" then return nil, "web page link" end
    if not sw or not sh or sw < 1 or sh < 1 then return nil, "needs converter", fmt end
    local tw, th = fitSize(sw, sh, ART.aw, ART.ah, ART.keep)
    local grid, err = Dec.decode(body, tw, th)
    if not grid then return nil, err, fmt, sw, sh end
    return grid, nil, fmt, sw, sh
end

local function loadImage()
    Dec.smooth = true
    Dec.linear = true
    local errors = {}
    local grid, fmt, sw, sh, via
    local body, err = httpGet(ART.url)
    if body then
        local g, e, f, w, h = tryDecode(body)
        if g then grid, fmt, sw, sh, via = g, f, w, h, "direct" else errors[#errors + 1] = tostring(e) end
    else
        errors[#errors + 1] = tostring(err)
    end
    if not grid and ART.url:match("^https?://") then
        local cu = "https://wsrv.nl/?url=" .. urlEncode(ART.url) .. "&w=" .. ART.aw .. "&h=" .. ART.ah
            .. "&fit=" .. (ART.keep and "inside" or "fill") .. "&output=png"
        local cbody, cerr = httpGet(cu)
        if cbody then
            local g, e, f, w, h = tryDecode(cbody)
            if g then
                grid, fmt, sw, sh, via = g, "converted", w, h, "converter"
            else
                errors[#errors + 1] = "converter: " .. tostring(e)
            end
        else
            errors[#errors + 1] = "converter: " .. tostring(cerr)
        end
    end
    if not grid then
        local why = table.concat(errors, " | ")
        say("Load failed: " .. (why ~= "" and why:sub(1, 200) or "unknown reason"))
        return false
    end
    sharpenGrid(grid, ART.sharpen)
    ART.grid, ART.fmt, ART.srcW, ART.srcH, ART.via = grid, fmt, sw, sh, via
    ART.tw, ART.th = grid.w, grid.h
    ART.ox = math.floor((ART.aw - ART.tw) / 2)
    ART.oy = math.floor((ART.ah - ART.th) / 2)
    say(string.format("Loaded (%s): %dx%d blocks.", tostring(via), ART.tw, ART.th))
    return true
end

-- two ways to say where the art goes: the middle + a size, or two opposite corners (the last one you set is used)
local function areaOf()
    if ART.areaMode == "corners" then
        if not (ART.p1 and ART.p2) then return nil end
        local minX, maxX = math.min(ART.p1.x, ART.p2.x), math.max(ART.p1.x, ART.p2.x)
        local minY, maxY = math.min(ART.p1.y, ART.p2.y), math.max(ART.p1.y, ART.p2.y)
        return minX, minY, maxX - minX + 1, maxY - minY + 1
    end
    if not ART.mid then return nil end
    local minX = ART.mid.x - math.floor((ART.sizeW - 1) / 2)
    local minY = ART.mid.y - math.floor((ART.sizeH - 1) / 2)
    return minX, minY, ART.sizeW, ART.sizeH
end

local function areaText()
    local minX, minY, aw, ah = areaOf()
    if ART.areaMode == "corners" then
        if not minX then return "Corners: set both (/pos1 and /pos2)" end
        return "Corners " .. ART.p1.x .. "," .. ART.p1.y .. " to " .. ART.p2.x .. "," .. ART.p2.y .. " = " .. aw .. "x" .. ah
    end
    if not minX then return "Middle: not set" end
    return "Middle " .. ART.mid.x .. "," .. ART.mid.y .. " = " .. aw .. "x" .. ah
end

local function areaProblem()
    local minX, minY, aw, ah = areaOf()
    if not minX then
        if ART.areaMode == "corners" then return "Set both corners first: stand on one and type /pos1, then the other and type /pos2." end
        if ART.p1 or ART.p2 then return "Set the other corner too (/pos1 and /pos2), or set the middle with /artmid." end
        return "Set the area first: the middle (/artmid) or two corners (/pos1 and /pos2)."
    end
    if aw * ah > MAX_BLOCKS then
        return "That is " .. (aw * ah) .. " blocks, more than the " .. MAX_BLOCKS .. " limit. Pick a smaller area."
    end
    return nil
end

local function signature()
    local _, _, aw, ah = areaOf()
    return table.concat({ ART.url, aw or 0, ah or 0, tostring(ART.keep), ART.sharpen }, "|")
end

local function prepareImage(thenDo)
    if ART.loading then return end
    if ART.url == "" then say("Enter an image link.") return end
    local problem = areaProblem()
    if problem then say(problem) return end
    local _, _, aw, ah = areaOf()
    ART.aw, ART.ah = aw, ah
    ART.loading = true
    ART.grid = nil
    say("Loading...")
    RunThread(function()
        Dec.yield = function() nap(1) end
        local ok, res = pcall(loadImage)
        ART.loading = false
        if ok and res then
            ART.sig = signature()
            if thenDo then thenDo() end
        end
    end)
end

-- ------------------------------------------------------------
--  building
-- ------------------------------------------------------------
local function timeLeft()
    if ART.done <= 0 then return "?" end
    local now = os.time()
    if not ART.paused then
        ART.activeTime = ART.activeTime + (now - ART.lastTickTime)
    end
    ART.lastTickTime = now
    if ART.activeTime <= 0 then return "?" end
    local rate = ART.done / ART.activeTime
    local remaining = ART.total - ART.done
    local left = math.floor(remaining / rate)
    if left < 0 then left = 0 end
    return string.format("%dm %02ds", math.floor(left / 60), left % 60)
end

local function waitWhilePaused()
    while ART.paused and not ART.cancel do nap(200) end
    ART.lastTickTime = os.time()
    return not ART.cancel
end

local function buildCell(x, y, r, g, b, dir)
    local why = "error"
    local attempts = 0
    while attempts < 4 do
        if ART.cancel then return false, "cancelled" end
        local have = invCount(ART_BLOCK_ID)
        if have ~= nil and have <= 0 then
            if not (ART.autoFind and restock()) then return false, "out of blocks" end
        else
            attempts = attempts + 1
            if not ensureReach(x, y, dir) then
                why = "cant reach"
                nap(ART.t.retryWait)
            elseif not placeAt(x, y) then
                why = "cant place"
                nap(ART.t.retryWait)
            else
                local ok, w2, fatal = colorBlock(x, y, r, g, b)
                if ok then return true end
                why = w2 or "color failed"
                if fatal then return false, why end
                nap(ART.t.retryWait)
            end
        end
    end
    return false, why
end

local function buildOrder(grid)
    local order = {}
    local tw, th = grid.w, grid.h
    for cy = 0, th - 1 do
        local from, to, step = 0, tw - 1, 1
        if cy % 2 == 1 then from, to, step = tw - 1, 0, -1 end
        for cx = from, to, step do
            local i = cy * tw + cx + 1
            if (grid.a[i] or 255) >= ALPHA_MIN then order[#order + 1] = i end
        end
    end
    return order
end

local function build()
    if ART.running then say("Already running.") return end
    if not ART.grid then say("Image not loaded.") return end
    local problem = areaProblem()
    if problem then say(problem) return end
    local minX, minY = areaOf()
    local grid = ART.grid
    local tw = grid.w
    ART.order = buildOrder(grid)
    local resume = resumePending and ART.total == #ART.order and ART.cursor >= 1 and ART.cursor <= #ART.order
    if not resume then ART.total, ART.cursor, ART.done = #ART.order, 1, 0 end
    resumePending = false
    if ART.total == 0 then say("Nothing to build.") return end
    saveSession()
    ART.running, ART.paused, ART.cancel = true, false, false
    ART.startedAt = os.time()
    ART.activeTime = 0
    ART.lastTickTime = ART.startedAt
    ART.hide = true
    if ART.modfly then setModfly(true) end
    say(string.format("Building %d blocks.", ART.total))

    RunThread(function()
        local lastCheckpoint = os.time()
        local ok, err = pcall(function()
            while ART.cursor <= ART.total do
                if not waitWhilePaused() then return end
                local i = ART.order[ART.cursor]
                local cx, cy = (i - 1) % tw, math.floor((i - 1) / tw)
                local x, y = minX + ART.ox + cx, minY + ART.oy + cy
                local dir = (cy % 2 == 0) and 1 or -1
                local done, why = buildCell(x, y, grid.r[i], grid.g[i], grid.b[i], dir)
                if done then
                    ART.cursor = ART.cursor + 1
                    ART.done = ART.done + 1
                    if ART.done % 10 == 0 or os.time() - lastCheckpoint >= 15 then
                        saveSession()
                        lastCheckpoint = os.time()
                    end
                    if ART.done % 25 == 0 then
                        say(string.format("Progress %d/%d (%d%%) Left: %s", ART.done, ART.total,
                            math.floor(ART.done * 100 / ART.total), timeLeft()))
                    end
                    nap(ART.t.blockGap)
                elseif ART.cancel then
                    return
                else
                    ART.paused = true
                    say(string.format("Paused at %d,%d: %s. Resume when ready.", x, y, tostring(why)))
                end
            end
        end)
        ART.running = false
        ART.hide = false
        saveSession()
        if ART.flying then setModfly(false) end
        if ART.cancel then say("Cancelled.")
        elseif ok then say("Finished!") end
    end)
end

local function startBuild()
    if ART.running then say("Already running.") return end
    local problem = areaProblem()
    if problem then say(problem) return end
    if ART.url == "" then say("Enter an image link.") return end
    if ART.grid and ART.sig == signature() then build() else prepareImage(build) end
end

local function testBlock()
    if ART.running then say("Running.") return end
    local minX, minY, aw, ah = areaOf()
    if not minX then say(areaProblem()) return end
    ART.hide = true
    RunThread(function()
        local x, y = minX + math.floor((aw - 1) / 2), minY + math.floor((ah - 1) / 2)
        local have = invCount(ART_BLOCK_ID)
        if have ~= nil and have <= 0 and not (ART.autoFind and restock()) then
            say("Test failed: you have no Kranken's Galactic Blocks.")
            ART.hide = false
            return
        end
        if not ensureReach(x, y, 1) then
            say("Test failed: could not get next to " .. x .. "," .. y .. " (no free tile to stand on).")
            ART.hide = false
            return
        end
        if not placeAt(x, y) then
            say("Test failed: the block did not place at " .. x .. "," .. y .. ".")
            ART.hide = false
            return
        end
        local success, why = colorBlock(x, y, 255, 0, 0)
        ART.hide = false
        if success then say("Test block placed.") else say("Test failed: " .. tostring(why or "colour step")) end
    end)
end

-- ------------------------------------------------------------
--  licence
-- ------------------------------------------------------------
local LOCK = { user = "indeacps", repo = "auto-art", branch = "main", file = "uids.txt" }
local AUTH = { ok = false, stopped = false, uid = nil, list = nil, fetchedAt = 0, msg = "Checking..." }
local HOOKS = { { "onvariant", "KRAKEN_ART_DIALOG" }, { "onsendpacket", "KRAKEN_ART_COMMANDS" }, { "onsendpacket", "KRAKEN_ART_MENU_ACTIONS" } }

-- the account that was checked must still be the account that is playing
-- (a nil / 0 id means logged out and is ignored until the id appears or changes)
local currentUid
local function allowed()
    if not AUTH.ok or AUTH.stopped then return false end
    local u = currentUid()
    return u == nil or u == AUTH.uid
end

local function authMsg()
    if AUTH.ok and not AUTH.stopped then return "Checking your account, one moment..." end
    return AUTH.msg
end

local function parseUidList(body)
    if type(body) ~= "string" or body == "" then return nil end
    local list = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$") or ""
        -- A line is an id on its own, or an id followed by a # note. Nothing else counts.
        local digits = line:match("^(%d+)$") or line:match("^(%d+)%s*#")
        if digits then
            local id = tonumber(digits)
            if id and id > 0 then list[id] = true end
        end
    end
    return list
end

currentUid = function()
    local p = GetLocal and GetLocal() or nil
    if not p then return nil end
    local u = tonumber(p.userid)
    if not u or u <= 0 then u = tonumber(p.userID) end
    if not u or u <= 0 then u = tonumber(p.user_id) end
    if not u or u <= 0 then u = tonumber(p.uid) end
    if u and u > 0 then return u end
    return nil
end

local function stopScript(why)
    AUTH.ok, AUTH.stopped = false, true
    AUTH.msg = why
    ART.cancel, ART.paused = true, false
    if RemoveHook then
        for _, h in ipairs(HOOKS) do
            pcall(RemoveHook, h[2])
            pcall(RemoveHook, h[1], h[2])
        end
    end
    say("Stopped: " .. why)
end

-- Reads the id every second (local, free). GitHub is asked when the id is new, and then every 15 seconds.
-- A nil / 0 id means the player logged out: it is ignored, nothing stops, until an id shows up again.
local function licenceLoop()
    local url = "https://raw.githubusercontent.com/" .. LOCK.user .. "/" .. LOCK.repo .. "/" .. LOCK.branch .. "/" .. LOCK.file
    local lastUid, lastCheck = nil, 0
    AUTH.msg = "Waiting for your user id..."
    while not AUTH.stopped do
        local uid = currentUid()
        if uid and (uid ~= lastUid or os.time() - lastCheck >= 15) then
            lastUid, lastCheck = uid, os.time()
            local body = httpGet(url .. "?t=" .. tostring(os.time()))
            local list = body and parseUidList(body) or nil
            if not list then
                AUTH.ok = false
                AUTH.msg = "Cannot verify licence (GitHub unavailable)"
            elseif list[uid] then
                if not AUTH.ok then say("Licence OK.") end
                AUTH.list, AUTH.fetchedAt = list, os.time()
                AUTH.uid, AUTH.ok, AUTH.msg = uid, true, "Licensed"
            else
                stopScript("UID not allowed")
                return
            end
        end
        nap(1000)
    end
end
-- ------------------------------------------------------------
--  menu
-- ------------------------------------------------------------
local function setMiddle()
    local x, y = getPos()
    if not x then say("Position error.") return end
    ART.mid = { x = x, y = y }
    ART.areaMode = "mid"
    ART.grid = nil
    saveSession()
    say("Middle set: " .. x .. ", " .. y .. "  (using middle + size)")
end

local function setCorner(n)
    local x, y = getPos()
    if not x then say("Position error.") return end
    ART["p" .. n] = { x = x, y = y }
    ART.grid = nil
    if ART.p1 and ART.p2 then
        ART.areaMode = "corners"
        local _, _, aw, ah = areaOf()
        say("Corner " .. n .. " set: " .. x .. ", " .. y .. "  (using corners: " .. aw .. "x" .. ah .. ")")
    else
        say("Corner " .. n .. " set: " .. x .. ", " .. y .. ". Now set corner " .. (n == 1 and 2 or 1) .. ".")
    end
    saveSession()
end

local function useArea(mode)
    if mode == "corners" and not (ART.p1 and ART.p2) then say("Set both corners first (/pos1 and /pos2).") return end
    if mode == "mid" and not ART.mid then say("Set the middle first (/artmid).") return end
    ART.areaMode = mode
    ART.grid = nil
    saveSession()
    say("Now using: " .. areaText())
end

local function dl(s) return (tostring(s or ""):gsub("[|\r\n]", " ")) end
local function newPage(title)
    return { "add_label_with_icon|big|`w" .. title .. "|left|" .. ART_BLOCK_ID .. "|", "add_spacer|small|" }
end
local function section(b, name) b[#b + 1] = "add_label|small|`5" .. name .. "|left|" b[#b + 1] = "add_spacer|small|" end
local function para(b, s) b[#b + 1] = "add_textbox|" .. dl(s) .. "|" end
local function note(b, s) b[#b + 1] = "add_smalltext|`7" .. dl(s) .. "|" end
local function btn(b, id, label) b[#b + 1] = "add_button|" .. id .. "|" .. dl(label) .. "|noflags|0|" end
local function inp(b, id, label, value, len) b[#b + 1] = "add_text_input|" .. id .. "|`1" .. dl(label) .. "|" .. dl(value) .. "|" .. (len or 6) .. "|" end
local function chk(b, id, label, on) b[#b + 1] = "add_checkbox|" .. id .. "|`3" .. dl(label) .. "|" .. (on and "1" or "0") .. "|" end
local function showPage(b, page)
    b[#b + 1] = "end_dialog|kraken_" .. page .. "|Close|Save|"
    SendVariantList({ [0] = "OnDialogRequest", [1] = table.concat(b, "\n") .. "\n" })
end

local DELAYS = {
    { "blockGap", "Block Delay", 0, 5000 },
    { "placeWait", "Place Wait", 20, 1000 },
    { "hopShort", "Short Teleport", 20, 2000 },
    { "hopLong", "Long Teleport", 20, 3000 },
}

local PAGES = {}

PAGES.home = function()
    local b = newPage("Kraken Art Maker")
    local mid = areaText()
    local img = ART.grid and (ART.tw .. "x" .. ART.th) or "None"
    local status = ART.running and (ART.paused and "`6Paused" or "`2Running") or "`4Idle"
    note(b, mid)
    note(b, "Img: " .. img .. " | Status: " .. status)
    note(b, AUTH.msg)
    b[#b + 1] = "add_spacer|small|"
    section(b, "Controls")
    btn(b, "act_start", "`3Start Building")
    btn(b, "act_pause", "`6Pause")
    btn(b, "act_resume", "`6Resume")
    btn(b, "act_cancel", "`4Cancel")
    section(b, "Menus")
    btn(b, "go_build", "`bArt Setup")
    btn(b, "go_speed", "`bDelays")
    btn(b, "go_tut", "`eHelp")
    showPage(b, "home")
end

PAGES.build = function()
    local b = newPage("Setup")
    section(b, "Config")
    inp(b, "art_url", "Link", ART.url, 300)
    inp(b, "art_size", "Size WxH (middle mode)", ART.sizeW .. "x" .. ART.sizeH, 9)
    chk(b, "art_keep", "Keep Ratio", ART.keep)
    inp(b, "art_sharp", "Sharpen", ART.sharpen, 3)
    note(b, "Using: " .. areaText())
    section(b, "Position: middle + size")
    btn(b, "act_mid", "`bSet Middle Here")
    section(b, "Position: two corners")
    btn(b, "act_pos1", "`bSet Corner 1 Here")
    btn(b, "act_pos2", "`bSet Corner 2 Here")
    section(b, "Which one to use")
    btn(b, "act_usemid", "`3Use Middle + Size")
    btn(b, "act_usecorners", "`3Use Corners")
    btn(b, "act_test", "`6Test Block")
    section(b, "ModFly")
    chk(b, "art_fly", "Modfly", ART.modfly)
    b[#b + 1] = "add_spacer|small|"
    btn(b, "go_home", "`4Back")
    showPage(b, "build")
end

PAGES.blocks = function()
    local b = newPage("Refill")
    section(b, "Options")
    chk(b, "art_find", "Auto Refill", ART.autoFind)
    inp(b, "art_refill", "Target Count", ART.refillTo, 5)
    b[#b + 1] = "add_spacer|small|"
    btn(b, "go_home", "`4Back")
    showPage(b, "blocks")
end

PAGES.speed = function()
    local b = newPage("Delays")
    section(b, "Timings")
    for _, d in ipairs(DELAYS) do inp(b, "t_" .. d[1], d[2], ART.t[d[1]], 5) end
    b[#b + 1] = "add_spacer|small|"
    btn(b, "act_reset", "`6Reset Defaults")
    btn(b, "go_home", "`4Back")
    showPage(b, "speed")
end

PAGES.tut = function()
    local b = newPage("Help")
    para(b, "Quick guide and instructions below.")
    btn(b, "go_tut1", "`bQuick Start")
    btn(b, "go_tut2", "`bCommands")
    btn(b, "go_tut3", "`bTroubleshooting")
    b[#b + 1] = "add_spacer|small|"
    btn(b, "go_home", "`4Back")
    showPage(b, "tut")
end

PAGES.tut1 = function()
    local b = newPage("Quick Start")
    para(b, "1. Paste a direct image link in the setup menu.")
    para(b, "2. Set your target size like 50x50.")
    para(b, "3. Pick ONE way to place it. Middle: stand at the center of your art and press Set Middle Here (size comes from the Size box). Corners: stand on one corner, press Set Corner 1, then stand on the opposite corner and press Set Corner 2. The last one you set is used.")
    para(b, "4. Test a block to make sure colors work properly.")
    para(b, "5. Click Start Building.")
    btn(b, "go_tut", "`4Back")
    showPage(b, "tut1")
end

PAGES.tut2 = function()
    local b = newPage("Commands")
    para(b, "/art - Open settings menu")
    para(b, "/artmid - Set art center position (uses the Size box)")
    para(b, "/pos1 and /pos2 - Set two opposite corners (size comes from the corners)")
    para(b, "/artpause - Pause the build process")
    para(b, "/artresume - Resume active building")
    para(b, "/artcancel - Cancel current build session")
    para(b, "/artstatus - Print status to console")
    btn(b, "go_tut", "`4Back")
    showPage(b, "tut2")
end

PAGES.tut3 = function()
    local b = newPage("Troubleshooting")
    para(b, "Safe pause: The script pauses if it cannot place or color a block. Fix the obstruction and click Resume.")
    para(b, "Direct links: Ensure links point straight to image files.")
    btn(b, "go_tut", "`4Back")
    showPage(b, "tut3")
end

local function openPage(name)
    if not allowed() then say(authMsg()) return end
    local f = PAGES[name] or PAGES.home
    f()
end

local APPLY = {}
APPLY.build = function(p)
    if field(p, "art_url") == nil then return end
    ART.url = cleanUrl(field(p, "art_url"))
    local w, h = parseSize(field(p, "art_size"))
    if w then
        -- typing a different size means "use the middle + size"
        if (w ~= ART.sizeW or h ~= ART.sizeH) and ART.mid and ART.areaMode == "corners" then
            ART.areaMode = "mid"
            say("Size changed: now using the middle + size.")
        end
        ART.sizeW, ART.sizeH = w, h
    end
    ART.keep = field(p, "art_keep") == "1"
    ART.sharpen = clamp(field(p, "art_sharp"), 0, 100)
    ART.modfly = field(p, "art_fly") == "1"
end
APPLY.blocks = function(p)
    if field(p, "art_find") == nil then return end
    ART.autoFind = field(p, "art_find") == "1"
    ART.refillTo = clamp(field(p, "art_refill"), 1, 20000)
end
APPLY.speed = function(p)
    if field(p, "t_" .. DELAYS[1][1]) == nil then return end
    for _, d in ipairs(DELAYS) do
        local v = field(p, "t_" .. d[1])
        if v ~= nil then ART.t[d[1]] = clamp(v, d[3], d[4]) end
    end
end

local DEFAULT_T = { blockGap = 100, placeWait = 60, retryWait = 350, dialogWait = 3000, hopShort = 130, hopLong = 260,
                    shortDist = 8, refillWait = 100, refillTimeout = 25 }

local ACTIONS = {
    act_start = function() startBuild() end,
    act_test = function() testBlock() end,
    act_mid = function() setMiddle() end,
    act_pos1 = function() setCorner(1) end,
    act_pos2 = function() setCorner(2) end,
    act_usemid = function() useArea("mid") end,
    act_usecorners = function() useArea("corners") end,
    act_pause = function() ART.paused = true saveSession() say("Paused.") end,
    act_resume = function()
        if not ART.running and resumePending and ART.grid then build()
        else ART.paused = false ART.lastTickTime = os.time() say("Resumed.") end
    end,
    act_cancel = function() ART.cancel = true ART.paused = false saveSession() say("Cancelled.") end,
    act_reset = function() for k, v in pairs(DEFAULT_T) do ART.t[k] = v end say("Delays reset.") end,
}

-- ------------------------------------------------------------
--  hooks
-- ------------------------------------------------------------
AddHook("onvariant", "KRAKEN_ART_DIALOG", function(v)
    if not v or v[0] ~= "OnDialogRequest" or type(v[1]) ~= "string" then return false end
    if ART.expect then
        ART.dlgBody = v[1]
        ART.expect = false
        return true
    end
    if ART.hide and ART.running then return true end
    return false
end)

AddHook("onsendpacket", "KRAKEN_ART_COMMANDS", function(packetType, packet)
    if type(packet) ~= "string" then return false end
    local msg = packet:match("action|input\n|text|([^\n]*)")
    if not msg then return false end
    msg = msg:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = msg:lower()
    if low:sub(1, 4) ~= "/art" and low ~= "/pos1" and low ~= "/pos2" then return false end
    if not allowed() then say(authMsg()) return true end
    if low == "/art" then openPage("home") return true end
    if low == "/artmid" then setMiddle() return true end
    if low == "/pos1" then setCorner(1) return true end
    if low == "/pos2" then setCorner(2) return true end
    if low == "/artpause" then ART.paused = true say("Paused.") return true end
    if low == "/artresume" then
        if not ART.running and resumePending and ART.grid then build()
        else ART.paused = false ART.lastTickTime = os.time() say("Resumed.") end
        return true
    end
    if low == "/artcancel" then ART.cancel = true ART.paused = false say("Cancelled.") return true end
    if low == "/artstatus" then
        local img = ART.grid and (ART.tw .. "x" .. ART.th) or "None"
        say(areaText() .. " | Image: " .. img)
        return true
    end
    if low:sub(1, 7) == "/artmap" then
        local map = {}
        for k, v in msg:gmatch("(%w+)=([^%s]+)") do
            k = k:lower()
            if k == "r" or k == "g" or k == "b" or k == "hex" then map[k] = v
            elseif k == "btn" or k == "button" then map.button = v end
        end
        if map.r or map.hex or map.button then
            ART.map = map
            say("Mapping saved.")
        else
            ART.map = nil
            say("Mapping cleared.")
        end
        return true
    end
    return false
end)

AddHook("onsendpacket", "KRAKEN_ART_MENU_ACTIONS", function(packetType, packet)
    if type(packet) ~= "string" then return false end
    local page = (field(packet, "dialog_name") or ""):match("^kraken_(%w+)$")
    if not page then return false end
    if not allowed() then say(authMsg()) return true end
    if APPLY[page] then APPLY[page](packet) saveSession() end
    local b = field(packet, "buttonClicked") or ""
    if b:sub(1, 3) == "go_" then
        openPage(b:sub(4))
    elseif ACTIONS[b] then
        ACTIONS[b]()
        if b == "act_reset" then openPage("speed")
        elseif b == "act_mid" or b == "act_pos1" or b == "act_pos2" or b == "act_usemid" or b == "act_usecorners" then openPage("build") end
    end
    return true
end)

local restored = loadSession()
if restored then say("Saved session restored. Use /artresume to continue the previous build.") end
RunThread(licenceLoop)
say("Loaded. Type /art to open the menu.")
