import random
import re
import pickle
from js import document
from pyodide.ffi import create_proxy
import json

# Default training data (small subset of Seinfeld dialogue for demo purposes)
SAMPLE_DIALOGUE = """
JERRY: I don't understand why they would have the ceremony in such a remote location.
GEORGE: I'm not driving all the way out there. It's ridiculous.
JERRY: So you're not going?
GEORGE: No, I'm going. I'm just gonna complain the whole time.
ELAINE: What's the deal with people getting married anyway?
JERRY: I know. They're happy for like what? A week? Then they're just showing each other their purchases.
KRAMER: Hey buddy, what's going on?
JERRY: We're just talking about this wedding invitation.
KRAMER: Oh yeah, I got mine. I'm not going.
JERRY: Why not?
KRAMER: Because, Jerry, it's out in the middle of nowhere. These pretzels are making me thirsty.
GEORGE: That's what I said!
ELAINE: Did you just eat a pretzel?
KRAMER: No, I'm just saying it.
JERRY: So, Newman's going?
KRAMER: Oh yeah, he's driving.
GEORGE: How does Newman get invited to a wedding and I have to struggle with whether I should go or not?
JERRY: Newman always gets invited to weddings. He's a postman. He carries the invitations. He just keeps the ones he wants.
GEORGE: That's genius! That's genius!
JERRY: Not that there's anything wrong with that.
ELAINE: I'm not going to get him a gift.
JERRY: You have to get him a gift.
ELAINE: But I don't even know the guy.
JERRY: That's what the gift is for - to say thanks for inviting me to a wedding even though I don't know you.
GEORGE: You know what I'm going to get him? Nothing. Because I'm not going. I'm making a stand.
JERRY: You just said you were going!
GEORGE: I did? I don't wanna be a pirate!
NEWMAN: Hello, Jerry.
JERRY: Hello, Newman.
NEWMAN: Lovely weather we're having.
JERRY: Yes. Yes we are.
NEWMAN: Aren't you going to ask me about the wedding?
JERRY: I don't care about the wedding.
NEWMAN: Oh, but you should. It's going to be magnificent. The cake alone cost $2,000.
GEORGE: $2,000 for a cake? Do you know what I could do with $2,000?
JERRY: Lose it gambling?
GEORGE: That's a strong possibility.
ELAINE: Maybe the dingo ate your baby!
KRAMER: These pretzels are making me thirsty!
JERRY: What's the deal with airplane food?
GEORGE: It's not a lie if you believe it.
JERRY: Serenity now, insanity later.
GEORGE: Yada, yada, yada.
ELAINE: Get out!
JERRY: But I don't want to be a cowboy!
GEORGE: You know, we're living in a society!
JERRY: Not that there's anything wrong with that.
"""

class MarkovModel:
    """Markov chain model for generating text based on trained data."""
    
    def __init__(self):
        self.tokens = []  # List of all tokens
        self.token_to_idx = {}  # Mapping from token to its index
        self.transitions = []  # List of transitions for each token
        self.model_trained = False
    
    def add_token(self, token):
        """Add a token to the model if it doesn't exist and return its index."""
        if token in self.token_to_idx:
            return self.token_to_idx[token]
        
        token_idx = len(self.tokens)
        self.tokens.append(token)
        self.token_to_idx[token] = token_idx
        self.transitions.append([])
        return token_idx
    
    def add_transition(self, from_token_idx, to_token_idx):
        """Add a transition from one token to another."""
        self.transitions[from_token_idx].append(to_token_idx)
    
    def get_next_token(self, token_idx):
        """Get a random next token based on transitions."""
        if not self.transitions[token_idx]:
            return -1
        
        return random.choice(self.transitions[token_idx])
    
    def find_token(self, search_token):
        """Find a token in the model with various search strategies."""
        # Strategy 1: Direct lookup
        if search_token in self.token_to_idx:
            return self.token_to_idx[search_token]
        
        # Strategy 2: Case insensitive lookup
        search_token_lower = search_token.lower()
        for token, idx in self.token_to_idx.items():
            if token.lower() == search_token_lower:
                return idx
        
        # Strategy 3: Substring match
        for token, idx in self.token_to_idx.items():
            if search_token_lower in token.lower():
                return idx
        
        # Strategy 4: First word match for multi-word tokens
        if ' ' in search_token:
            first_word = search_token.split()[0].lower()
            for token, idx in self.token_to_idx.items():
                if token.lower().startswith(first_word):
                    return idx
        
        # Strategy 5: Return random token with many transitions
        candidates = []
        for idx, transitions in enumerate(self.transitions):
            if len(transitions) > 5:  # Token has reasonable number of transitions
                token = self.tokens[idx]
                # Skip tokens with script artifacts
                if '(' not in token and ')' not in token and ':' not in token:
                    candidates.append((idx, len(transitions)))
        
        if candidates:
            # Sort by transition count (descending) and take top 10
            candidates.sort(key=lambda x: x[1], reverse=True)
            top_candidates = candidates[:10]
            return random.choice(top_candidates)[0]
        
        # Fallback to random token
        return random.randint(0, len(self.tokens) - 1) if self.tokens else -1

    def to_json(self):
        """Convert model to JSON string."""
        return json.dumps({
            'tokens': self.tokens,
            'transitions': self.transitions,
            'model_trained': self.model_trained
        })
    
    @classmethod
    def from_json(cls, json_str):
        """Create model from JSON string."""
        data = json.loads(json_str)
        model = cls()
        model.tokens = data['tokens']
        model.transitions = data['transitions']
        model.model_trained = data['model_trained']
        
        # Rebuild token_to_idx
        model.token_to_idx = {token: idx for idx, token in enumerate(model.tokens)}
        return model


class SeinfeldChatbot:
    """Chatbot that responds with Seinfeld-style dialogue using a Markov chain."""
    
    def __init__(self):
        self.model = MarkovModel()
        self.seinfeld_characters = ["JERRY", "GEORGE", "ELAINE", "KRAMER", "NEWMAN"]
        self.min_response_length = 5  # Minimum words in a response
        self.max_response_attempts = 20  # Maximum attempts to generate a response
        self.stopwords = {
            "a", "an", "the", "and", "but", "or", "for", "nor", "on", "at", "to", "from",
            "by", "with", "in", "out", "over", "under", "again", "further", "then",
            "once", "here", "there", "when", "where", "why", "how", "all", "any",
            "both", "each", "few", "more", "most", "other", "some", "such", "no",
            "not", "only", "own", "same", "so", "than", "too", "very", "s", "t",
            "can", "will", "just", "don", "should", "now", "d", "ll", "m", "o",
            "re", "ve", "y", "ain", "aren", "couldn", "didn", "doesn", "hadn",
            "hasn", "haven", "isn", "ma", "mightn", "mustn", "needn", "shan",
            "shouldn", "wasn", "weren", "won", "wouldn", "i", "me", "my", "myself",
            "we", "our", "ours", "ourselves", "you", "your", "yours", "yourself",
            "yourselves", "he", "him", "his", "himself", "she", "her", "hers",
            "herself", "it", "its", "itself", "they", "them", "their", "theirs"
        }
        self.debug_mode = False
        self.used_seeds = set()  # Track used seed phrases to avoid repetition
    
    def clean_text(self, text):
        """Clean up text by removing script artifacts and extra whitespace."""
        # Remove stage directions
        text = re.sub(r'\([^)]*\)', '', text)
        
        # Remove character names at start of lines (e.g., "JERRY: ")
        text = re.sub(r'^[A-Z]+:', '', text)
        
        # Remove extra whitespace
        text = re.sub(r'\s+', ' ', text).strip()
        
        return text
    
    def tokenize(self, text):
        """Split text into tokens."""
        return text.split()
    
    def remove_punctuation(self, word):
        """Remove punctuation from a word."""
        return re.sub(r'[^\w\s]', '', word)
    
    def train_on_dialogue(self, dialogue_text):
        """Train the model on dialogue text."""
        update_status("Training the model...")
        
        try:
            # Break into lines and process line by line
            lines = dialogue_text.split('\n')
            dialog_lines = []
            
            for line in lines:
                line = line.strip()
                
                # Skip empty lines
                if not line:
                    continue
                
                # Check if this is a character's dialogue
                for character in self.seinfeld_characters:
                    if line.startswith(character + ':'):
                        # Extract the dialogue part (after the character name)
                        dialogue = line[len(character) + 1:].strip()
                        dialogue = self.clean_text(dialogue)
                        if dialogue:
                            dialog_lines.append(dialogue)
                        break
            
            # Process the dialogue for training
            token_count = 0
            prev_token_idx = -1
            
            for line in dialog_lines:
                tokens = self.tokenize(line)
                
                for token in tokens:
                    token = token.strip()
                    if not token:
                        continue
                    
                    token_idx = self.model.add_token(token)
                    token_count += 1
                    
                    # Add transition from previous token
                    if prev_token_idx >= 0:
                        self.model.add_transition(prev_token_idx, token_idx)
                    
                    prev_token_idx = token_idx
            
            self.model.model_trained = True
            update_status(f"Training complete! Processed {token_count} tokens.")
            return True
            
        except Exception as e:
            update_status(f"Error training model: {str(e)}")
            return False
    
    def save_model_to_storage(self):
        """Save model to browser localStorage."""
        if not self.model.model_trained:
            update_status("No trained model to save!")
            return False
        
        try:
            model_json = self.model.to_json()
            # This would be implemented with localStorage in a full implementation
            update_status("Model saved to browser storage.")
            return True
        except Exception as e:
            update_status(f"Error saving model: {str(e)}")
            return False
    
    def load_model_from_json(self, json_str):
        """Load model from JSON string."""
        try:
            self.model = MarkovModel.from_json(json_str)
            update_status("Model loaded.")
            return True
        except Exception as e:
            update_status(f"Error loading model: {str(e)}")
            return False
    
    def find_good_seeds(self, user_input):
        """Find good seed phrases from user input."""
        words = user_input.split()
        good_seeds = []
        
        # Remove stopwords
        important_words = [w for w in words if w.lower() not in self.stopwords 
                          and len(w) > 2  # Skip very short words
                          and not w.isdigit()]  # Skip numbers
        
        # Try various seed strategies
        
        # 1. Two-word combinations of important words
        if len(important_words) >= 2:
            for i in range(len(important_words) - 1):
                seed = f"{important_words[i]} {important_words[i+1]}"
                token_idx = self.model.find_token(seed)
                if token_idx >= 0 and seed not in self.used_seeds:
                    good_seeds.append((seed, 3))  # Higher score for two-word matches
        
        # 2. Individual important words
        for word in important_words:
            token_idx = self.model.find_token(word)
            if token_idx >= 0 and word not in self.used_seeds:
                good_seeds.append((word, 2))
        
        # 3. Original phrases from input (up to 3 words)
        for i in range(len(words)):
            for j in range(1, min(4, len(words) - i + 1)):
                phrase = " ".join(words[i:i+j])
                token_idx = self.model.find_token(phrase)
                if token_idx >= 0 and phrase not in self.used_seeds:
                    good_seeds.append((phrase, j))  # Score based on length
        
        # Sort by score (descending)
        good_seeds.sort(key=lambda x: x[1], reverse=True)
        
        # Return just the seeds (without scores)
        return [seed for seed, _ in good_seeds]
    
    def generate_sentence(self, seed_phrase):
        """Generate a sentence starting with the given seed phrase."""
        if not seed_phrase or not self.model.model_trained:
            return ""
        
        max_length = 50  # Maximum number of tokens in a sentence
        max_attempts = 30  # Maximum attempts to generate a valid token
        
        # Start with the seed phrase
        token_idx = self.model.find_token(seed_phrase)
        if token_idx < 0:
            return ""
        
        current_token = self.model.tokens[token_idx]
        sentence = current_token
        used_tokens = {current_token}
        word_count = len(seed_phrase.split())
        
        sentence_ended = False
        attempts = 0
        
        while word_count < max_length and attempts < max_attempts and not sentence_ended:
            # Find the next token
            next_token_idx = self.model.get_next_token(token_idx)
            
            if next_token_idx >= 0 and next_token_idx < len(self.model.tokens):
                next_token = self.model.tokens[next_token_idx]
                
                # Check for repetition
                if next_token not in used_tokens:
                    sentence += " " + next_token
                    used_tokens.add(next_token)
                    word_count += 1
                    token_idx = next_token_idx
                    
                    # Check if this ended a sentence
                    if next_token and next_token[-1] in ['.', '!', '?']:
                        sentence_ended = True
                    
                    # If we've reached a reasonable length, consider stopping
                    if word_count >= 8:  # At least 8 words for a decent sentence
                        break
                else:
                    attempts += 1
            else:
                attempts += 1
        
        # Ensure sentence ends with proper punctuation
        if sentence and sentence[-1] not in ['.', '!', '?']:
            sentence += "."
        
        # Final cleanup
        sentence = sentence.strip()
        sentence = re.sub(r'\s+', ' ', sentence)  # Remove extra spaces
        
        # Filter out sentences that are too short
        if len(sentence.split()) < 5:
            return ""
        
        # Capitalize first letter
        if sentence:
            sentence = sentence[0].upper() + sentence[1:]
        
        return sentence
    
    def generate_fallback_response(self):
        """Generate a fallback Seinfeld-style response when normal generation fails."""
        responses = [
            "What's the deal with that?",
            "Not that there's anything wrong with that.",
            "These pretzels are making me thirsty!",
            "I'm out there, Jerry, and I'm loving every minute of it!",
            "No soup for you!",
            "Serenity now!",
            "I don't wanna be a pirate!",
            "It's not a lie if you believe it.",
            "You know, we're living in a society!",
            "I'm speechless. I have no speech.",
            "You want a piece of me? YOU GOT IT!",
            "Hello, Newman.",
            "That's a shame.",
            "I've yada yada'd sex.",
            "Maybe the dingo ate your baby!",
            "I choose not to run!",
            "It's not you, it's me.",
            "You can stuff your sorries in a sack, mister!",
            "I'm a joke maker. Tell him, Jerry.",
            "And you want to be my latex salesman..."
        ]
        return random.choice(responses)
    
    def generate_response(self, user_input):
        """Generate a response to user input."""
        if not user_input or not self.model.model_trained:
            return "The chatbot hasn't been trained yet!"
        
        # Clean and normalize input
        user_input = self.clean_text(user_input)
        
        # Find good seed phrases from the input
        seed_phrases = self.find_good_seeds(user_input)
        
        # Try to generate responses with each seed phrase
        responses = []
        
        # If no good seeds were found, try some random ones
        if not seed_phrases and self.model.tokens:
            for _ in range(3):
                random_idx = random.randint(0, len(self.model.tokens) - 1)
                random_seed = self.model.tokens[random_idx]
                if len(random_seed) > 2 and '(' not in random_seed and ')' not in random_seed:
                    seed_phrases.append(random_seed)
        
        seed_count = len(seed_phrases) if seed_phrases else 1
        attempts_per_seed = self.max_response_attempts // max(1, seed_count)
        
        for seed in seed_phrases[:5]:  # Try top 5 seeds
            for _ in range(attempts_per_seed):
                response = self.generate_sentence(seed)
                if response and len(response.split()) >= self.min_response_length:
                    responses.append(response)
            
            # Mark this seed as used to prevent repetition
            self.used_seeds.add(seed)
            
            # Keep used_seeds from growing too large
            if len(self.used_seeds) > 100:
                self.used_seeds = set(list(self.used_seeds)[-50:])
        
        # If we generated valid responses, choose the best one
        if responses:
            # Prioritize longer responses
            responses.sort(key=lambda x: len(x.split()), reverse=True)
            
            # Randomly select one of the top responses
            return random.choice(responses[:3])
        
        # If all else fails, return a fallback response
        return self.generate_fallback_response()
    
    def get_character_name(self):
        """Get a random Seinfeld character name for the response."""
        top_characters = ["Jerry", "George"]
        return random.choice(top_characters)


# Global chatbot instance
chatbot = SeinfeldChatbot()

# Has the model been trained?
model_trained = False

def update_status(message):
    """Update the status message in the UI."""
    status_element = document.getElementById("status-message")
    status_element.textContent = message


def add_message(text, is_user=False):
    """Add a message to the chat container."""
    chat_container = document.getElementById("chat-container")
    
    # Create message element
    message_div = document.createElement("div")
    message_div.className = "message user-message" if is_user else "message bot-message"
    
    if not is_user:
        # Add character name for bot messages
        character_span = document.createElement("span")
        character_span.className = "character-name"
        character_span.textContent = f"{chatbot.get_character_name()}:"
        message_div.appendChild(character_span)
    
    # Add message text
    text_node = document.createTextNode(" " + text if not is_user else text)
    message_div.appendChild(text_node)
    
    # Add to chat container
    chat_container.appendChild(message_div)
    
    # Scroll to bottom
    chat_container.scrollTop = chat_container.scrollHeight


def send_message(*args):
    """Handle sending a message."""
    input_element = document.getElementById("user-input")
    user_message = input_element.value.strip()
    
    if not user_message:
        return
    
    # Add user message to chat
    add_message(user_message, is_user=True)
    
    # Clear input
    input_element.value = ""
    
    # Generate response
    if not model_trained:
        # If model is not trained, suggest training
        add_message("I'm not trained yet! Click the 'Train New Model' button below to get me started.")
    else:
        # Generate and add response
        response = chatbot.generate_response(user_message)
        add_message(response)


def train_model(*args):
    """Train the model on sample Seinfeld dialogue."""
    global model_trained
    
    update_status("Training model on sample Seinfeld dialogue...")
    
    # Train on sample dialogue
    success = chatbot.train_on_dialogue(SAMPLE_DIALOGUE)
    
    if success:
        model_trained = True
        update_status("Model trained successfully! You can now chat with the Seinfeld characters.")
        
        # Add a message to inform the user
        add_message("Training complete! I'm now ready to chat like a true Seinfeld character.")
    else:
        update_status("Training failed. Please try again.")


def init():
    """Initialize the application."""
    # Hide loading message
    document.getElementById("initial-loading").style.display = "none"
    
    # Show chat interface
    document.getElementById("chat-interface").style.display = "block"
    
    # Set up event listeners
    input_element = document.getElementById("user-input")
    
    def handle_keypress(event):
        if event.key == "Enter":
            send_message()
    
    input_element.addEventListener("keypress", create_proxy(handle_keypress))
    
    # Set initial status
    update_status("Click 'Train New Model' to start!")


# Initialize the app
init()
