''=====================================================================
'' poemshow.bas -- "Three Poems" : a visual poetry reading
'' by Ronen Blumberg, visuals engine built with Claude
''
'' 800x600, 32-bit, FreeBASIC + BASS
'' Uses Ronen's modules: fb_samples_init.bas / fb_images_init.bas
''
'' Needs in the same folder:
''   A_Boy_Wakes_Up_in_the_Morning.mp3
''   Honor_Thy_Father_and_Thy_Mother.mp3
''   Life_Is_Pain-2.mp3
''   ronen1.bmp  ronen1_retro.bmp  ronen1_duo.bmp
''   ronen2.bmp  ronen2_retro.bmp  ronen2_duo.bmp
''
'' Keys: ESC quit | SPACE pause | M next scene | N next poem
''
'' Compile (Linux):   fbc poemshow.bas -l bass
''=====================================================================
#ifdef __FB_JS__ 
#cmdline " -Wl '--embed-file gfx' "
#endif


#include "fbgfx.bi"
Using FB

#include "fb_samples_init.bas"      '' Ronen's BASS init + playMusic
#include "fb_images_init.bas"       '' Ronen's BMP loader

'' web build: supply the BASS analysis functions the fbjs shim lacks
#if defined(__FB_JS__) or defined(WEBBUILD)
    #include "bass_webviz.bi"
#endif

Const SCR_W = 800
Const SCR_H = 600
Const CX    = SCR_W \ 2
Const CY    = SCR_H \ 2
Const PI2   = 6.2831853

Const NBARS = 96
Const NWAVE = 512
Const NPART = 300
Const NSTAR = 90

'' scene ids
Const SCN_NEBULA   = 0
Const SCN_OCEAN    = 1
Const SCN_PULSE    = 2
Const SCN_SUNRISE  = 3
Const SCN_CANDLES  = 4
Const SCN_PORTRAIT = 5

''---------------------------------------------------------------------
'' shared state
''---------------------------------------------------------------------
Dim Shared As Single g_fft(1023)
Dim Shared As Single g_wave(2047)
Dim Shared As Single g_bars(NBARS-1)
Dim Shared As Single g_bassEnergy, g_midEnergy, g_avgEnergy
Dim Shared As Integer g_beat
Dim Shared As Single g_beatGlow
Dim Shared As Single g_hue, g_hueBase
Dim Shared As Single g_rot
Dim Shared As Integer g_pitch

Type Particle
    x As Single
    y As Single
    vx As Single
    vy As Single
    life As Single
    hue As Single
End Type
Dim Shared As Particle g_part(NPART-1)

Type Star
    x As Single
    y As Single
    spd As Single
    phase As Single
End Type
Dim Shared As Star g_star(NSTAR-1)

'' photos: index 0 = close-up portrait, 1 = waving portrait
Dim Shared As fb.image Ptr g_photo(1), g_retro(1), g_duo(1)
Dim Shared As fb.image Ptr g_chanR(1), g_chanC(1)   '' channel-split copies
Dim Shared As Integer g_hasPhotos

'' per-poem config, filled in main
Dim Shared As fb.image Ptr g_portraitImg     '' image used by SCN_PORTRAIT
Dim Shared As fb.image Ptr g_flashImg        '' image flashed on big beats
Dim Shared As Integer g_flashFrames

''---------------------------------------------------------------------
'' HSV -> RGB
''---------------------------------------------------------------------
Function hsv(ByVal h As Single, ByVal s As Single, ByVal v As Single) As ULong
    h = h Mod 360 : If h < 0 Then h += 360
    If v < 0 Then v = 0
    If v > 1 Then v = 1
    Dim As Single c = v * s
    Dim As Single x = c * (1 - Abs((h / 60) Mod 2 - 1))
    Dim As Single m = v - c
    Dim As Single r, g, b
    Select Case Int(h / 60)
        Case 0 : r = c : g = x : b = 0
        Case 1 : r = x : g = c : b = 0
        Case 2 : r = 0 : g = c : b = x
        Case 3 : r = 0 : g = x : b = c
        Case 4 : r = x : g = 0 : b = c
        Case Else : r = c : g = 0 : b = x
    End Select
    Return RGB((r+m)*255, (g+m)*255, (b+m)*255)
End Function

''---------------------------------------------------------------------
'' fade toward black (trails) - call inside ScreenLock
''---------------------------------------------------------------------
Sub fadeScreen()
    Dim As UByte Ptr row0 = ScreenPtr()
    If row0 = 0 Then Exit Sub
    For y As Integer = 0 To SCR_H - 1
        Dim As ULong Ptr p = Cast(ULong Ptr, row0 + y * g_pitch)
        For x As Integer = 0 To SCR_W - 1
            Dim As ULong c = p[x]
            p[x] = c - ((c Shr 3) And &h1F1F1F)
        Next
    Next
End Sub

''---------------------------------------------------------------------
'' big text: at fixed x (for typewriter) and centered
''---------------------------------------------------------------------
Sub bigTextAt(ByVal s As String, ByVal px As Integer, ByVal py As Integer, _
              ByVal sc As Integer, ByVal col As ULong)
    If Len(s) = 0 Then Exit Sub
    Dim As Integer w = Len(s) * 8, h = 8
    Dim As fb.image Ptr img = ImageCreate(w, h, RGB(0,0,0))
    If img = 0 Then Exit Sub
    Draw String img, (0,0), s, RGB(255,255,255)
    For yy As Integer = 0 To h - 1
        For xx As Integer = 0 To w - 1
            If Point(xx, yy, img) <> RGB(0,0,0) Then
                Line (px + xx*sc, py + yy*sc)-Step(sc-1, sc-1), col, BF
            End If
        Next
    Next
    ImageDestroy(img)
End Sub

Sub bigText(ByVal s As String, ByVal py As Integer, ByVal sc As Integer, _
            ByVal col As ULong)
    bigTextAt(s, CX - (Len(s) * 8 * sc) \ 2, py, sc, col)
End Sub

'' pick largest scale that fits the screen width
Function fitScale(ByVal s As String) As Integer
    Dim As Integer sc = 3
    While sc > 1 And Len(s) * 8 * sc > SCR_W - 24
        sc -= 1
    Wend
    Return sc
End Function

''---------------------------------------------------------------------
'' audio analysis + beat detection
''---------------------------------------------------------------------
Sub analyzeAudio(ByVal chan As DWORD)
    BASS_ChannelGetData(chan, @g_fft(0), BASS_DATA_FFT2048)
    BASS_ChannelGetData(chan, @g_wave(0), (2048 * SizeOf(Single)) Or BASS_DATA_FLOAT)

    Dim As Single e = 0
    For i As Integer = 1 To 10
        e += g_fft(i)
    Next
    g_bassEnergy = e

    Dim As Single em = 0
    For i As Integer = 15 To 80        '' voice band
        em += g_fft(i)
    Next
    g_midEnergy = em

    g_avgEnergy = g_avgEnergy * 0.96 + e * 0.04

    Static As Single cooldown
    cooldown -= 1
    g_beat = 0
    If e > g_avgEnergy * 1.35 And e > 0.05 And cooldown <= 0 Then
        g_beat = 1
        g_beatGlow = 1.0
        cooldown = 12
    End If
    If g_beatGlow > 0 Then g_beatGlow -= 0.05

    For b As Integer = 0 To NBARS - 1
        Dim As Integer i0 = Int(Exp(Log(700.0) * b / NBARS))
        Dim As Integer i1 = Int(Exp(Log(700.0) * (b+1) / NBARS))
        If i1 <= i0 Then i1 = i0 + 1
        Dim As Single peak = 0
        For i As Integer = i0 To i1
            If g_fft(i) > peak Then peak = g_fft(i)
        Next
        Dim As Single v = Sqr(peak) * 2.2
        If v > 1 Then v = 1
        If v > g_bars(b) Then g_bars(b) = v Else g_bars(b) *= 0.88
    Next
End Sub

''---------------------------------------------------------------------
'' particles (radial bursts + rising sparks)
''---------------------------------------------------------------------
Sub spawnBurst(ByVal n As Integer)
    Dim As Integer made = 0
    For i As Integer = 0 To NPART - 1
        If g_part(i).life <= 0 Then
            Dim As Single a = Rnd * PI2
            Dim As Single sp = 2 + Rnd * 5 + g_bassEnergy * 8
            g_part(i).x = CX : g_part(i).y = CY
            g_part(i).vx = Cos(a) * sp
            g_part(i).vy = Sin(a) * sp
            g_part(i).life = 0.6 + Rnd * 0.8
            g_part(i).hue = g_hue + Rnd * 60
            made += 1
            If made >= n Then Exit For
        End If
    Next
End Sub

Sub spawnSpark(ByVal sx As Single, ByVal sy As Single)
    For i As Integer = 0 To NPART - 1
        If g_part(i).life <= 0 Then
            g_part(i).x = sx + (Rnd-0.5) * 10
            g_part(i).y = sy
            g_part(i).vx = (Rnd-0.5) * 0.8
            g_part(i).vy = -(0.8 + Rnd * 1.6 + g_midEnergy * 2)
            g_part(i).life = 0.8 + Rnd * 1.0
            g_part(i).hue = 30 + Rnd * 30
            Exit For
        End If
    Next
End Sub

Sub updateParticles()
    For i As Integer = 0 To NPART - 1
        If g_part(i).life > 0 Then
            g_part(i).x += g_part(i).vx
            g_part(i).y += g_part(i).vy
            g_part(i).vx *= 0.985
            g_part(i).vy *= 0.985
            g_part(i).life -= 0.015
            Circle (g_part(i).x, g_part(i).y), 1.5, _
                   hsv(g_part(i).hue, 0.9, g_part(i).life), , , , F
        End If
    Next
End Sub

''---------------------------------------------------------------------
'' photo helpers
''---------------------------------------------------------------------
Sub buildChannels(ByVal idx As Integer)
    Dim As Integer w, h, bypp, spit, dpitR, dpitC
    Dim As Any Ptr sp, dpR, dpC
    If g_photo(idx) = 0 Then Exit Sub
    If ImageInfo(g_photo(idx), w, h, bypp, spit, sp) <> 0 Then Exit Sub
    g_chanR(idx) = ImageCreate(w, h, RGB(0,0,0))
    g_chanC(idx) = ImageCreate(w, h, RGB(0,0,0))
    If g_chanR(idx) = 0 Or g_chanC(idx) = 0 Then Exit Sub
    Dim As Integer dw, dh, db
    If ImageInfo(g_chanR(idx), dw, dh, db, dpitR, dpR) <> 0 Then Exit Sub
    If ImageInfo(g_chanC(idx), dw, dh, db, dpitC, dpC) <> 0 Then Exit Sub
    For y As Integer = 0 To h - 1
        Dim As ULong Ptr srow = Cast(ULong Ptr, sp + y * spit)
        Dim As ULong Ptr rrow = Cast(ULong Ptr, dpR + y * dpitR)
        Dim As ULong Ptr crow = Cast(ULong Ptr, dpC + y * dpitC)
        For x As Integer = 0 To w - 1
            Dim As ULong c = srow[x]
            rrow[x] = c And &hFF0000        '' red channel only
            crow[x] = c And &h00FFFF        '' green + blue
        Next
    Next
End Sub

'' chromatic aberration glitch (only for photos with channel copies)
Sub chromaPut(ByVal idx As Integer, ByVal dx As Integer)
    If idx < 0 Then Exit Sub
    If g_chanR(idx) = 0 Then Exit Sub
    If dx < 1 Then dx = 1
    If dx > 30 Then dx = 30
    Put (0, 0), g_chanR(idx), (dx, 0)-(SCR_W-1, SCR_H-1), PSet
    Put (dx, 0), g_chanC(idx), (0, 0)-(SCR_W-1-dx, SCR_H-1), Add, 255
End Sub

'' shift random horizontal strips of an image (VHS glitch)
Sub glitchSlices(ByVal img As fb.image Ptr, ByVal maxOff As Integer, _
                 ByVal n As Integer)
    If img = 0 Then Exit Sub
    For i As Integer = 1 To n
        Dim As Integer y0 = Int(Rnd * (SCR_H - 40))
        Dim As Integer hh = 6 + Int(Rnd * 30)
        Dim As Integer dx = Int((Rnd - 0.5) * 2 * maxOff)
        If dx >= 0 Then
            Put (dx, y0), img, (0, y0)-(SCR_W-1-dx, y0+hh), PSet
        Else
            Put (0, y0), img, (-dx, y0)-(SCR_W-1, y0+hh), PSet
        End If
    Next
End Sub

Sub scanLines(ByVal stp As Integer)
    For y As Integer = 0 To SCR_H - 1 Step stp
        Line (0, y)-(SCR_W-1, y), RGB(0, 0, 0)
    Next
End Sub

''---------------------------------------------------------------------
'' intro / outro photo card with typewriter title
''---------------------------------------------------------------------
Sub drawIntro(ByVal img As fb.image Ptr, ByVal chromaIdx As Integer, _
              ByVal ttl As String, ByVal byline As String, _
              ByVal elap As Single, ByVal glitchAmt As Single)
    If img Then
        Put (0, 0), img, PSet
        If glitchAmt > 0.02 Then
            If Rnd < glitchAmt Then chromaPut(chromaIdx, 2 + Int(Rnd * 12))
            If Rnd < glitchAmt Then glitchSlices(img, 26, 10)
        End If
        scanLines(3)
    Else
        Line (0,0)-(SCR_W-1, SCR_H-1), RGB(6,4,14), BF
    End If

    '' bottom title panel
    Line (0, 468)-(SCR_W-1, SCR_H-1), RGB(8, 6, 16), BF
    Line (0, 468)-(SCR_W-1, 468), hsv(g_hue, 0.8, 0.85)
    Line (0, 470)-(SCR_W-1, 470), hsv(g_hue + 40, 0.8, 0.45)

    Dim As Integer sc = fitScale(ttl)
    Dim As Integer nchars = Int(elap * 16)
    If nchars > Len(ttl) Then nchars = Len(ttl)
    Dim As Integer px = CX - (Len(ttl) * 8 * sc) \ 2
    bigTextAt(Left(ttl, nchars), px, 492, sc, hsv(g_hue + 30, 0.35, 0.95))
    '' blinking cursor while typing
    If nchars < Len(ttl) And Frac(Timer * 3) < 0.5 Then
        Line (px + nchars*8*sc, 492)-Step(8, 8*sc), hsv(g_hue, 0.8, 1), BF
    End If
    Draw String (CX - Len(byline)*4, 545), byline, RGB(205, 205, 220)
End Sub

''---------------------------------------------------------------------
'' SCENE: Nebula
''---------------------------------------------------------------------
Sub sceneNebula()
    For b As Integer = 0 To NBARS - 1
        Dim As Single a = g_rot + PI2 * b / NBARS
        Dim As Single r0 = 170 + g_beatGlow * 14
        Dim As Single r1 = r0 + 12 + g_bars(b) * 150
        Dim As ULong c = hsv(g_hue + b * 2.2, 0.85, 0.35 + g_bars(b) * 0.65)
        Line (CX + Cos(a)*r0, CY + Sin(a)*r0)- _
             (CX + Cos(a)*r1, CY + Sin(a)*r1), c
    Next
    Dim As Single px, py, fx, fy
    For i As Integer = 0 To NWAVE - 1
        Dim As Single s = (g_wave(i*2) + g_wave(i*2+1)) * 0.5
        Dim As Single a = -g_rot * 0.7 + PI2 * i / NWAVE
        Dim As Single r = 120 + s * 90 + g_beatGlow * 10
        Dim As Single nx = CX + Cos(a) * r
        Dim As Single ny = CY + Sin(a) * r
        If i = 0 Then
            fx = nx : fy = ny
        Else
            Line (px, py)-(nx, ny), hsv(g_hue + 180, 0.7, 0.9)
        End If
        px = nx : py = ny
    Next
    Line (px, py)-(fx, fy), hsv(g_hue + 180, 0.7, 0.9)
    Dim As Single cr = 18 + g_bassEnergy * 90 + g_beatGlow * 22
    Circle (CX, CY), cr,     hsv(g_hue, 0.5, 0.55 + g_beatGlow * 0.45), , , , F
    Circle (CX, CY), cr + 5, hsv(g_hue, 0.9, 0.9)
End Sub

''---------------------------------------------------------------------
'' SCENE: Ocean
''---------------------------------------------------------------------
Sub sceneOcean()
    For ch As Integer = 0 To 1
        Dim As Single px, py
        Dim As Integer baseY = CY - 80 + ch * 160
        For i As Integer = 0 To NWAVE - 1
            Dim As Single s = g_wave(i*2 + ch)
            Dim As Single nx = i * (SCR_W / NWAVE)
            Dim As Single ny = baseY + s * (120 + g_beatGlow * 60)
            If i > 0 Then Line (px, py)-(nx, ny), _
                               hsv(g_hue + ch*120 + i*0.3, 0.8, 0.9)
            px = nx : py = ny
        Next
    Next
    Dim As Integer half = NBARS \ 2
    Dim As Single bw = SCR_W / NBARS
    For b As Integer = 0 To NBARS - 1
        Dim As Integer src = Abs(b - half)
        Dim As Single hgt = g_bars(src) * 190 + 2
        Line (b*bw + 1, SCR_H - hgt)-(b*bw + bw - 2, SCR_H - 1), _
             hsv(g_hue + src * 3, 0.9, 0.3 + g_bars(src) * 0.7), BF
    Next
End Sub

''---------------------------------------------------------------------
'' SCENE: Pulse (FFT-warped rose)
''---------------------------------------------------------------------
Sub scenePulse()
    Dim As Single px, py, fx, fy
    Const NPTS = 360
    For i As Integer = 0 To NPTS - 1
        Dim As Single a = g_rot + PI2 * i / NPTS
        Dim As Integer barIdx = (i * NBARS \ NPTS)
        Dim As Single r = 120 + Sin(a * 5 + g_rot * 3) * 40 _
                        + g_bars(barIdx) * 160 + g_beatGlow * 20
        Dim As Single nx = CX + Cos(a) * r
        Dim As Single ny = CY + Sin(a) * r * 0.85
        If i = 0 Then
            fx = nx : fy = ny
        Else
            Line (px, py)-(nx, ny), hsv(g_hue + i, 0.85, 0.9)
        End If
        px = nx : py = ny
    Next
    Line (px, py)-(fx, fy), hsv(g_hue, 0.85, 0.9)
    If g_beat Then spawnBurst(40)
End Sub

''---------------------------------------------------------------------
'' SCENE: Sunrise  (sun climbs with the poem's progress)
''---------------------------------------------------------------------
Sub sceneSunrise(ByVal prog As Single)
    Const HORIZON = 400
    Dim As Single sy = 520 - prog * 340

    '' glow halo
    For i As Integer = 5 To 1 Step -1
        Circle (CX, sy), 30 + i*24 + g_bassEnergy*55, _
               hsv(18 + i*7, 1, 0.10 + g_beatGlow*0.05), , , , F
    Next
    '' sun disc
    Circle (CX, sy), 34 + g_beatGlow*10, hsv(45, 0.75, 1), , , , F
    Circle (CX, sy), 35 + g_beatGlow*10, hsv(30, 0.9, 0.9)

    '' horizon
    Line (0, HORIZON)-(SCR_W-1, HORIZON), hsv(28, 0.6, 0.55)

    '' sea reflections shimmering with the spectrum
    Dim As Single bw = SCR_W / NBARS
    For b As Integer = 0 To NBARS - 1
        Dim As Single shim = Sin(Timer*4 + b*0.7) * 6
        Dim As Single hgt = g_bars(b) * 150 + 4 + shim
        If hgt < 2 Then hgt = 2
        Line (b*bw + bw/2, HORIZON + 3)- _
             (b*bw + bw/2, HORIZON + 3 + hgt), _
             hsv(20 + g_bars(b)*45, 0.85, 0.22 + g_bars(b)*0.6)
    Next

    '' thin waveform drifting in the sky
    Dim As Single px, py
    For i As Integer = 0 To NWAVE - 1
        Dim As Single s = (g_wave(i*2) + g_wave(i*2+1)) * 0.5
        Dim As Single nx = i * (SCR_W / NWAVE)
        Dim As Single ny = 110 + s * 55
        If i > 0 Then Line (px, py)-(nx, ny), hsv(35, 0.5, 0.55)
        px = nx : py = ny
    Next
End Sub

''---------------------------------------------------------------------
'' SCENE: Candles  (solemn: two flames, rising sparks, stars)
''---------------------------------------------------------------------
Sub sceneCandles()
    '' twinkling stars
    For i As Integer = 0 To NSTAR - 1
        Dim As Single tw = 0.25 + 0.75 * Abs(Sin(Timer * g_star(i).spd + g_star(i).phase))
        PSet (g_star(i).x, g_star(i).y * 0.55), hsv(50, 0.15, tw)
    Next

    For c As Integer = 0 To 1
        Dim As Single fx = 250 + c * 300
        Dim As Single fh = 46 + g_midEnergy * 130 + Rnd * 8 + g_beatGlow * 30
        Dim As Single fy = 430 - fh / 2

        '' halo
        For i As Integer = 4 To 1 Step -1
            Circle (fx, fy), fh/2 + i*16, hsv(35, 1, 0.05 + g_midEnergy*0.06), , , , F
        Next
        '' flame (tall ellipses)
        Circle (fx, fy), fh/2, hsv(28, 1, 0.85), , , 2.4, F
        Circle (fx, fy + fh*0.12), fh/3.2, hsv(48, 0.85, 1), , , 2.2, F
        Circle (fx, fy + fh*0.22), fh/6, hsv(55, 0.3, 1), , , 2.0, F

        '' candle body
        Line (fx - 14, 432)-(fx + 14, 560), RGB(225, 218, 200), BF
        Line (fx - 14, 432)-(fx + 14, 560), RGB(120, 110, 95), B
        Line (fx - 14, 448)-(fx + 14, 448), RGB(190, 180, 160)

        If Rnd < 0.35 + g_midEnergy Then spawnSpark(fx, fy - fh/2)
    Next
End Sub

''---------------------------------------------------------------------
'' SCENE: Portrait  (the poet, ghosted + audio-glitched)
''---------------------------------------------------------------------
Sub scenePortrait()
    If g_portraitImg = 0 Then
        scenePulse()
        Exit Sub
    End If
    Put (0, 0), g_portraitImg, Alpha, 60
    If g_beatGlow > 0.55 Then glitchSlices(g_portraitImg, 22, 8)
    scanLines(4)

    '' voice waveform running across the portrait
    Dim As Single px, py
    For i As Integer = 0 To NWAVE - 1
        Dim As Single s = (g_wave(i*2) + g_wave(i*2+1)) * 0.5
        Dim As Single nx = i * (SCR_W / NWAVE)
        Dim As Single ny = 440 + s * 90
        If i > 0 Then Line (px, py)-(nx, ny), hsv(g_hue + 180, 0.75, 0.95)
        px = nx : py = ny
    Next

    '' slim spectrum at the very bottom
    Dim As Single bw = SCR_W / NBARS
    For b As Integer = 0 To NBARS - 1
        Dim As Single hgt = g_bars(b) * 60 + 1
        Line (b*bw + 1, SCR_H - hgt)-(b*bw + bw - 2, SCR_H - 1), _
             hsv(g_hue + b*3, 0.9, 0.3 + g_bars(b)*0.7), BF
    Next
End Sub

''=====================================================================
'' MAIN
''=====================================================================
ScreenRes SCR_W, SCR_H, 32
WindowTitle "Three Poems -- written & read by Ronen Blumberg"

Scope
    Dim As Integer w, h, depth, bpp
    ScreenInfo w, h, depth, bpp, g_pitch
End Scope

Randomize Timer
For i As Integer = 0 To NSTAR - 1
    g_star(i).x = Rnd * SCR_W
    g_star(i).y = Rnd * SCR_H
    g_star(i).spd = 1 + Rnd * 3
    g_star(i).phase = Rnd * PI2
Next

'' ---- load the poet (Ronen's loadImage1; web build packages gfx/) ----
Function loadPhoto(ByVal fname As String) As fb.image Ptr
    Dim As fb.image Ptr img = loadImage1("gfx/" & fname)
    If img = 0 Then img = loadImage1(fname)
    Return img
End Function

g_photo(0) = loadPhoto("ronen1.bmp")
g_photo(1) = loadPhoto("ronen2.bmp")
g_retro(0) = loadPhoto("ronen1_retro.bmp")
g_retro(1) = loadPhoto("ronen2_retro.bmp")
g_duo(0)   = loadPhoto("ronen1_duo.bmp")
g_duo(1)   = loadPhoto("ronen2_duo.bmp")
g_hasPhotos = (g_photo(0) <> 0) And (g_photo(1) <> 0)
If g_hasPhotos Then
    buildChannels(0)
    buildChannels(1)
End If

'' ---- the programme ----
Const NPOEMS = 3
Dim As String poemFile(NPOEMS-1) = { "A_Boy_Wakes_Up_in_the_Morning.mp3", _
                                     "Honor_Thy_Father_and_Thy_Mother.mp3", _
                                     "Life_Is_Pain-2.mp3" }
Dim As String poemTitle(NPOEMS-1) = { "A BOY WAKES UP IN THE MORNING", _
                                      "HONOR THY FATHER AND THY MOTHER", _
                                      "LIFE IS PAIN" }
Dim As Single poemHue(NPOEMS-1) = { 25, 45, 215 }

'' scene sets: three scenes per poem, no two poems alike
Dim As Integer sceneSet(NPOEMS-1, 2) = _
    { { SCN_SUNRISE,  SCN_OCEAN,    SCN_NEBULA }, _
      { SCN_CANDLES,  SCN_PORTRAIT, SCN_PULSE  }, _
      { SCN_NEBULA,   SCN_PORTRAIT, SCN_PULSE  } }

'' intro card image + chroma index per poem
Dim As fb.image Ptr introImg(NPOEMS-1)
Dim As Integer introChroma(NPOEMS-1)
introImg(0) = g_photo(0) : introChroma(0) = 0        '' clean close-up
introImg(1) = g_duo(1)   : introChroma(1) = -1       '' duotone waving
introImg(2) = g_retro(0) : introChroma(2) = -1       '' synthwave dither

Dim As fb.image Ptr portraitFor(NPOEMS-1)
portraitFor(0) = 0                                   '' no portrait scene
portraitFor(1) = g_duo(0)
portraitFor(2) = g_retro(1)

Dim As fb.image Ptr flashFor(NPOEMS-1)
flashFor(0) = g_retro(0)
flashFor(1) = g_duo(1)
flashFor(2) = g_retro(1)

Dim As Integer wantQuit = 0
Dim As Integer beatCount = 0

For p As Integer = 0 To NPOEMS - 1
    Dim As DWORD chan = playMusic(poemFile(p))
    If chan = 0 Then
        Print "Skipping " ; poemFile(p) ; "  (BASS error " ; _
              BASS_ErrorGetCode() ; ")"
        Sleep 1500, 1
        Continue For
    End If

    Dim As Double songLen = BASS_ChannelBytes2Seconds(chan, _
                            BASS_ChannelGetLength(chan, BASS_POS_BYTE))
    g_hueBase = poemHue(p)
    g_portraitImg = portraitFor(p)
    g_flashImg = flashFor(p)
    g_flashFrames = 0

    Dim As Integer sceneSlot = 0
    Dim As Integer paused = 0
    Dim As Double sceneClock = Timer
    Dim As Double startT = Timer
    Dim As Double lastT = Timer
    Const INTRO_SECS = 7.0

    Do
        '' ---- input ----
        Dim As String k = Inkey
        If k = " " Then
            paused = 1 - paused
            If paused Then BASS_ChannelPause(chan) Else BASS_ChannelPlay(chan, 0)
        ElseIf LCase(k) = "m" Then
            sceneSlot = (sceneSlot + 1) Mod 3
            sceneClock = Timer
        ElseIf LCase(k) = "n" Then
            Exit Do
        End If
        If MultiKey(SC_ESCAPE) Then wantQuit = 1 : Exit Do

        If Timer - sceneClock > 22 Then
            sceneSlot = (sceneSlot + 1) Mod 3
            sceneClock = Timer
        End If

        '' ---- audio ----
        If paused = 0 Then analyzeAudio(chan)
        If g_beat Then
            beatCount += 1
            If sceneSet(p, sceneSlot) <> SCN_PULSE Then spawnBurst(14)
            '' every 7th beat: subliminal flash of the poet
            If g_hasPhotos And (beatCount Mod 7 = 0) Then g_flashFrames = 7
        End If

        '' ---- motion ----
        Dim As Double t = Timer
        Dim As Single dt = t - lastT
        lastT = t
        g_hue = g_hueBase + Sin(t * 0.2) * 45 + g_bassEnergy * 6
        g_rot += dt * (0.25 + g_bassEnergy * 0.8)

        Dim As Double posSec = BASS_ChannelBytes2Seconds(chan, _
                               BASS_ChannelGetPosition(chan, BASS_POS_BYTE))
        '' on web, duration only becomes known once metadata loads
        If songLen <= 0 Then
            songLen = BASS_ChannelBytes2Seconds(chan, _
                      BASS_ChannelGetLength(chan, BASS_POS_BYTE))
        End If
        Dim As Single prog = 0
        If songLen > 0 Then prog = posSec / songLen

        Dim As Double elap = Timer - startT

        '' ---- draw ----
        ScreenLock
            If elap < INTRO_SECS Then
                '' opening card: portrait + typewriter title
                Dim As Single glitchAmt = 0.08
                If elap > INTRO_SECS - 1.4 Then glitchAmt = 0.7   '' glitch out
                If elap < 0.6 Then glitchAmt = 0.6               '' glitch in
                drawIntro(introImg(p), introChroma(p), poemTitle(p), _
                          "written & read by Ronen Blumberg", elap, glitchAmt)
            Else
                fadeScreen()

                Select Case sceneSet(p, sceneSlot)
                    Case SCN_NEBULA   : sceneNebula()
                    Case SCN_OCEAN    : sceneOcean()
                    Case SCN_PULSE    : scenePulse()
                    Case SCN_SUNRISE  : sceneSunrise(prog)
                    Case SCN_CANDLES  : sceneCandles()
                    Case SCN_PORTRAIT : scenePortrait()
                End Select

                updateParticles()

                '' subliminal poet flash on the big beats
                If g_flashFrames > 0 And g_flashImg <> 0 Then
                    Put (0, 0), g_flashImg, Alpha, 26 + g_flashFrames * 6
                    g_flashFrames -= 1
                End If

                '' poem title, small, top-left
                Draw String (10, 8), poemTitle(p), _
                            hsv(g_hue + 30, 0.3, 0.55 + g_beatGlow * 0.3)
                Draw String (10, 20), "poem " & (p+1) & " / " & NPOEMS, _
                            RGB(110, 110, 130)

                '' progress bar
                If songLen > 0 Then
                    Line (60, SCR_H-14)-(SCR_W-60, SCR_H-8), RGB(50,50,60), B
                    Line (61, SCR_H-13)- _
                         (61 + (SCR_W-122) * prog, SCR_H-9), _
                         hsv(g_hue, 0.7, 0.9), BF
                End If
                If paused Then bigText("PAUSED", CY - 24, 4, RGB(255,255,255))
            End If
        ScreenUnlock

        If BASS_ChannelIsActive(chan) = BASS_ACTIVE_STOPPED Then Exit Do
        Sleep 15, 1
    Loop

    stopMusic()
    freeMusic()
    If wantQuit Then Exit For

    '' short breath of darkness between poems
    For f As Integer = 0 To 45
        ScreenLock : fadeScreen() : ScreenUnlock
        Sleep 15, 1
    Next
Next

'' ---- outro: the poet waves goodbye ----
If wantQuit = 0 Then
    Dim As Double outT = Timer
    Do While Timer - outT < 8
        If MultiKey(SC_ESCAPE) Then Exit Do
        ScreenLock
            drawIntro(g_photo(1), 1, "THANK YOU FOR LISTENING", _
                      "toda raba  --  shalom", Timer - outT, 0.10)
        ScreenUnlock
        Sleep 15, 1
    Loop
End If

For f As Integer = 0 To 60
    ScreenLock : fadeScreen() : ScreenUnlock
    Sleep 15, 1
Next

BASS_Free()
End 0
