''=====================================================================
'' bass_webviz.bi -- Web Audio bridge for BASS analysis calls
''
'' Supplies bodies for the BASS functions the fbjs web shim doesn't
'' implement, using the browser's AnalyserNode:
''   BASS_ChannelGetData      (FFT2048 + float waveform)
''   BASS_ChannelIsActive
''   BASS_ChannelGetLength / GetPosition   (fake "bytes" = milliseconds)
''   BASS_ChannelBytes2Seconds             (ms / 1000)
''   BASS_ErrorGetCode
''
'' Include AFTER fb_samples_init.bas (needs bass.bi's declares/constants),
'' only in the js build:
''   #if defined(__FB_JS__) or defined(WEBBUILD)
''       #include "bass_webviz.bi"
''   #endif
''=====================================================================

#ifndef BASS_WEBVIZ_BI
#define BASS_WEBVIZ_BI

#ifndef BASS_DATA_FLOAT
    #error "bass_webviz.bi must be included after bass.bi"
#endif

'' the Mysoft toolchain may already have included emscripten.bi
'' (it has no include guard of its own, so only pull it in if needed)
#ifndef EMSCRIPTEN_KEEPALIVE
    #include "emscripten.bi"
#endif

''---------------------------------------------------------------------
'' one-time page hook (runs at include point, before any playMusic):
'' wrap Audio creation so every element the shim makes is routed
'' through a shared AnalyserNode (fftSize 2048 -> 1024 bins, same as
'' BASS_DATA_FFT2048)
''---------------------------------------------------------------------
Scope
    Dim As String js = _
      "if(!window.__bviz){var V=window.__bviz={ctx:null,an:null,cur:null};" & _
      "V.hook=function(el){try{if(el.__bv)return;" & _
      "if(!V.ctx)V.ctx=new(window.AudioContext||window.webkitAudioContext)();" & _
      "if(!V.an){V.an=V.ctx.createAnalyser();V.an.fftSize=2048;" & _
      "V.an.smoothingTimeConstant=0.45;V.an.connect(V.ctx.destination);}" & _
      "V.ctx.createMediaElementSource(el).connect(V.an);el.__bv=1;V.cur=el;" & _
      "console.log('bviz: hooked',el.src||el);" & _
      "el.addEventListener('play',function(){V.cur=el;" & _
      "if(V.ctx.state!=='running')V.ctx.resume();});" & _
      "}catch(e){console.log('bviz hook:',e);}};" & _
      "['click','keydown','touchstart'].forEach(function(ev){" & _
      "document.addEventListener(ev,function(){" & _
      "if(V.ctx&&V.ctx.state!=='running')V.ctx.resume();},true);});" & _
      "var OP=HTMLMediaElement.prototype.play;" & _
      "HTMLMediaElement.prototype.play=function(){V.hook(this);V.cur=this;" & _
      "if(V.ctx&&V.ctx.state!=='running')V.ctx.resume();" & _
      "return OP.apply(this,arguments);};" & _
      "var OA=window.Audio;" & _
      "window.Audio=function(u){var el=(u===undefined)?new OA():new OA(u);" & _
      "V.hook(el);return el;};" & _
      "window.Audio.prototype=OA.prototype;" & _
      "var CE=document.createElement.bind(document);" & _
      "document.createElement=function(t){var el=CE(t);" & _
      "if((''+t).toLowerCase()==='audio')V.hook(el);return el;};" & _
      "document.querySelectorAll('audio').forEach(V.hook);}"
    emscripten_run_script(StrPtr(js))
End Scope

Extern "C"

''---------------------------------------------------------------------
Function BASS_ChannelGetData(ByVal handle As DWORD, _
                             ByVal buffer As Any Ptr, _
                             ByVal flags As DWORD) As DWORD
    Dim As String js
    Dim As UInteger p = Cast(UInteger, buffer)

    If flags = BASS_DATA_FFT2048 Then
        '' AnalyserNode gives dB; convert to linear magnitude like BASS
        js = "(function(p){var V=window.__bviz;if(!V||!V.an)return 0;" & _
             "var H=(typeof HEAPF32!=='undefined')?HEAPF32:Module.HEAPF32;" & _
             "if(!H)return 0;" & _
             "var n=V.an.frequencyBinCount,a=new Float32Array(n);" & _
             "V.an.getFloatFrequencyData(a);" & _
             "var m=(n<1024)?n:1024;for(var i=0;i<m;i++){var d=a[i];" & _
             "H[(p>>2)+i]=" & _
             "(isFinite(d)&&d>-120)?Math.pow(10,d/20):0;}" & _
             "return m*4;})(" & p & ")"
        Return emscripten_run_script_int(StrPtr(js))

    ElseIf (flags And BASS_DATA_FLOAT) <> 0 Then
        '' time-domain floats; analyser is mono, duplicate into L/R pairs
        Dim As Integer nf = (flags And &h0FFFFFFF) \ 4
        js = "(function(p,nf){var V=window.__bviz;if(!V||!V.an)return 0;" & _
             "var H=(typeof HEAPF32!=='undefined')?HEAPF32:Module.HEAPF32;" & _
             "if(!H)return 0;" & _
             "var a=new Float32Array(V.an.fftSize);" & _
             "V.an.getFloatTimeDomainData(a);" & _
             "var fr=nf>>1;for(var i=0;i<fr;i++){" & _
             "var v=(i<a.length)?a[i]:0;" & _
             "H[(p>>2)+2*i]=v;" & _
             "H[(p>>2)+2*i+1]=v;}" & _
             "return nf*4;})(" & p & "," & nf & ")"
        Return emscripten_run_script_int(StrPtr(js))
    End If
    Return 0
End Function

''---------------------------------------------------------------------
Function BASS_ChannelIsActive(ByVal handle As DWORD) As DWORD
    Dim As String js = _
        "(function(){var V=window.__bviz;if(!V||!V.cur)return -1;" & _
        "return V.cur.ended?0:(V.cur.paused?3:1);})()"
    Dim As Long r = emscripten_run_script_int(StrPtr(js))
    If r < 0 Then Return 1        '' nothing hooked yet: report playing
    Return r                       '' 0 stopped / 1 playing / 3 paused
End Function

''---------------------------------------------------------------------
'' positions: we use milliseconds as the "byte" unit, so
'' Bytes2Seconds is simply /1000 and everything stays consistent
''---------------------------------------------------------------------
Function BASS_ChannelGetLength(ByVal handle As DWORD, _
                               ByVal mode As DWORD) As QWORD
    Dim As String js = _
        "(function(){var V=window.__bviz;if(!V||!V.cur)return 0;" & _
        "var d=V.cur.duration;" & _
        "return isFinite(d)?Math.floor(d*1000):0;})()"
    Return emscripten_run_script_int(StrPtr(js))
End Function

Function BASS_ChannelGetPosition(ByVal handle As DWORD, _
                                 ByVal mode As DWORD) As QWORD
    Dim As String js = _
        "(function(){var V=window.__bviz;if(!V||!V.cur)return 0;" & _
        "return Math.floor(V.cur.currentTime*1000);})()"
    Return emscripten_run_script_int(StrPtr(js))
End Function

Function BASS_ChannelBytes2Seconds(ByVal handle As DWORD, _
                                   ByVal posbytes As QWORD) As Double
    Return posbytes / 1000.0
End Function

''---------------------------------------------------------------------
Function BASS_ErrorGetCode() As Long
    Return 0
End Function

End Extern

#endif  '' BASS_WEBVIZ_BI
