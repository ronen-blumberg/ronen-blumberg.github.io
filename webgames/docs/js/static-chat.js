// Static version of the Rachel chatbot for GitHub Pages 
"use strict"; 
 
// Audio player 
const audioPlayer = new Audio(); 
 
// Predefined responses based on keywords 
const responses = { 
  "hello": ["Hello. I'm Rachel.", "Hello. Nice to meet you.", "Hi there. My name is Rachel."], 
  "about": ["I'm Rachel. I'm a replicant, but I have memories. Some of them are real.", 
           "My name is Rachel. I work for the Tyrell Corporation.", 
           "I'm different than you are. I have implanted memories."], 
  "memories": ["I have memories, but I'm not sure they're mine. They might be implants.", 
             "I remember my mother. I remember looking up at her.", 
             "I have photos. A mother, father. But I know they aren't real."], 
  "play green": ["[PLAY:green.mp3] Here's the green sound you requested.", 
               "Here's green for you. [PLAY:green.mp3]"], 
  "default": ["I'm not sure I understand what you mean.", 
            "That's interesting. Tell me more.", 
            "I haven't been programmed with a response for that.", 
            "All those moments will be lost in time, like tears in rain."] 
}; 
 
// Text-to-speech 
const synth = window.speechSynthesis; 
let ziraVoice = null; 
 
// Load available voices 
function loadVoices() { 
  const voices = synth.getVoices(); 
