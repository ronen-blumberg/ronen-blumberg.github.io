#include "bass.bi"
#include "crt.bi"

If (BASS_Init(-1, 44100, 0, 0, 0) = 0) Then
    Print "Could not initialize BASS"
    End 1
End If

' Background music variables
dim shared as HMUSIC g_BackgroundMusic

' Sound effect variables - array for multiple sounds
const MAX_SOUNDS = 6  ' Adjust this based on your needs
dim shared as HSAMPLE g_SoundEffects(MAX_SOUNDS - 1)
dim shared as HCHANNEL g_Channels(MAX_SOUNDS - 1)

' Original music functions
sub stopMusic( music as HMUSIC = NULL )
  if music = NULL then music = g_BackgroundMusic
  if music then BASS_ChannelStop( music )
end sub

sub freeMusic( music as HMUSIC = NULL )
  if music = NULL then music = g_BackgroundMusic : g_BackgroundMusic = NULL
  if music then BASS_MusicFree( music )  
end sub

function playMusic( soundfile as string ) as HMUSIC
  if g_BackgroundmUsic then 
      stopMusic(g_BackgroundMusic)
      freeMusic(g_BackgroundMusic)
      g_BackgroundMusic = NULL
  EndIf
  var music = BASS_StreamCreateFile( 0, strptr( soundfile ), 0, 0, 0 )  
  if music then 
    g_BackgroundMusic = music
    BASS_ChannelPlay( music, 0 )
  end if
  return music
end Function

' New multiple sound effect functions
function loadSoundEffect(soundfile as string, index as integer) as HSAMPLE
    if index >= 0 and index < MAX_SOUNDS then
        var sample = BASS_SampleLoad(FALSE, strptr(soundfile), 0, 0, 1, BASS_SAMPLE_OVER_POS)
        if sample then
            g_SoundEffects(index) = sample
        end if
        return sample
    end if
    return 0
end function

function playSoundEffect(index as integer) as HCHANNEL
    if index >= 0 and index < MAX_SOUNDS then
        if g_SoundEffects(index) then
            g_Channels(index) = BASS_SampleGetChannel(g_SoundEffects(index), FALSE)
            if g_Channels(index) then
                BASS_ChannelPlay(g_Channels(index), TRUE)
            end if
            return g_Channels(index)
        end if
    end if
    return 0
end function

'sub freeSoundEffects()
'    for i as integer = 0 to MAX_SOUNDS - 1
'        if g_SoundEffects(i) then 
'            BASS_SampleFree(g_SoundEffects(i))
'            g_SoundEffects(i) = 0
'            g_Channels(i) = 0
'        end if
'    next
'end sub
