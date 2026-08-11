// Static version of Rachel chatbot for GitHub Pages 
const audioPlayer = new Audio(); 
 
// Predefined responses 
const responses = { 
  hello: ["Hello. I'm Rachel.", "Hello. Nice to meet you.", "Hi there. My name is Rachel."], 
  about: ["I'm Rachel. I'm a replicant, but I have memories.", "My name is Rachel. I work for the Tyrell Corporation."], 
  memories: ["I have memories, but I'm not sure they're mine.", "I remember my mother. I remember looking up at her."], 
  "play green": ["[PLAY:green.mp3] Here's the green sound you requested.", "Here's green for you. [PLAY:green.mp3]"], 
  default: ["I'm not sure I understand what you mean.", "That's interesting. Tell me more."] 
}; 
 
// Speech synthesis setup 
const synth = window.speechSynthesis; 
let voice = null; 
 
function loadVoices() { 
  const voices = synth.getVoices(); 
} 
 
loadVoices(); 
if (speechSynthesis.onvoiceschanged !== undefined) { 
  speechSynthesis.onvoiceschanged = loadVoices; 
} 
 
// Initialize chat 
document.addEventListener('DOMContentLoaded', function() { 
  // Add initial greeting 
  setTimeout(function() { 
    addMessage("Rachel", "Hello. I'm Rachel. How can I help you today?"); 
    speakText("Hello. I'm Rachel. How can I help you today?"); 
  }, 1000); 
 
  // Set up event listeners 
  document.getElementById("sendButton").addEventListener("click", sendMessage); 
  document.getElementById("messageInput").addEventListener("keypress", function(e) { 
    if (e.key === "Enter") { 
      sendMessage(); 
      e.preventDefault(); 
    } 
  }); 
}); 
 
function sendMessage() { 
  const input = document.getElementById("messageInput"); 
  const message = input.value.trim(); 
 
  if (message) { 
    addMessage("You", message); 
    input.value = ""; 
 
    // Process after a short delay 
    setTimeout(function() { 
      const response = getResponse(message); 
      addMessage("Rachel", response.text); 
      speakText(response.text); 
 
      if (response.audio) { 
        playAudio(response.audio); 
      } 
    }, 800); 
  } 
} 
 
function getResponse(message) { 
  const lowerMsg = message.toLowerCase(); 
  let result = { text: "", audio: null }; 
 
  // Check each response category 
  for (const [key, values] of Object.entries(responses)) { 
    if (lowerMsg.includes(key)) { 
      const idx = Math.floor(Math.random() * values.length); 
      result.text = values[idx]; 
 
      // Check for audio command 
      if (result.text.includes("[PLAY:")) { 
        const start = result.text.indexOf("[PLAY:") + 6; 
        const end = result.text.indexOf("]", start); 
        result.audio = result.text.substring(start, end); 
        result.text = result.text.replace("[PLAY:" + result.audio + "]", ""); 
      } 
 
      return result; 
    } 
  } 
 
  // Default response 
  const defaults = responses.default; 
  result.text = defaults[Math.floor(Math.random() * defaults.length)]; 
  return result; 
} 
 
function addMessage(user, message) { 
  const container = document.getElementById("messagesList"); 
  const msgDiv = document.createElement("div"); 
  msgDiv.classList.add("message", user === "You" ? "user-message" : "rachel-message"); 
 
  const nameSpan = document.createElement("span"); 
  nameSpan.classList.add("user-name"); 
  nameSpan.textContent = user + ": "; 
 
  const textSpan = document.createElement("span"); 
  textSpan.textContent = message; 
 
  msgDiv.appendChild(nameSpan); 
  msgDiv.appendChild(textSpan); 
  container.appendChild(msgDiv); 
 
  // Scroll to bottom 
  container.scrollTop = container.scrollHeight; 
} 
 
function speakText(text) { 
  synth.cancel(); 
 
  const utterance = new SpeechSynthesisUtterance(text); 
  if (voice) { 
    utterance.voice = voice; 
  } 
 
  synth.speak(utterance); 
} 
 
function playAudio(filename) { 
  audioPlayer.pause(); 
  console.log("Playing:", filename); 
 
  audioPlayer.src = "audio/" + filename; 
 
  audioPlayer.onerror = function(e) { 
    console.error("Audio error:", e); 
  }; 
 
  audioPlayer.play().catch(function(err) { 
    console.error("Play failed:", err); 
  }); 
} 
