// Radio station definitions using WebAssembly module
class RadioPlayer {
    constructor() {
        this.audio = new Audio();
        this.currentStation = null;
        this.timeUpdateInterval = null;
        this.metadataInterval = null;
        this.stations = [
            {
                index: 0,
                name: "Love Radio Cebu",
                location: "Cebu City, The Philippines",
                url: "http://stream.btsstream.com:8090/loveradio.mp3",
                utcOffset: 8
            },
            {
                index: 1,
                name: "Radio Cubana",
                location: "Cuba",
                url: "http://panel.streamenviron.com:8286/stream.mp3",
                utcOffset: -5
            },
            {
                index: 2,
                name: "Deep In Space Radio",
                location: "Russia",
                url: "http://i-radio.info:8000/radio",
                utcOffset: 3
            },
            {
                index: 3,
                name: "BBC Drama SciFi Radio",
                location: "UK",
                url: "http://s1.voscast.com:8652/stream",
                utcOffset: 0
            },
            {
                index: 4,
                name: "Rock Radio",
                location: "Germany",
                url: "http://stream.laut.fm/rock",
                utcOffset: 1
            }
        ];

        // Set audio preferences
        this.audio.preload = "none";  // Don't preload until play is clicked
        this.audio.volume = 0.8;      // Set initial volume
        
        // Wait for WASM to initialize
        if (typeof Module !== 'undefined') {
            Module.onRuntimeInitialized = () => {
                // Verify stations match with WebAssembly module
                for (let i = 0; i < this.stations.length; i++) {
                    const wasmStationInfo = Module.getStationInfo(i);
                    const wasmStationUrl = Module.getStationUrl(i);
                    console.log(`Station ${i} WASM info: ${wasmStationInfo}`);
                    console.log(`Station ${i} WASM URL: ${wasmStationUrl}`);
                }
                this.initializeUI();
                this.setupEventListeners();
            };
        } else {
            console.error('WebAssembly Module not loaded');
            this.initializeUI();
            this.setupEventListeners();
        }
    }

    initializeUI() {
        const stationList = document.getElementById('station-list');
        if (!stationList) {
            console.error('Station list element not found');
            return;
        }
        stationList.innerHTML = ''; // Clear existing stations
        
        // Add volume control
        const volumeControl = document.createElement('div');
        volumeControl.className = 'volume-control';
        volumeControl.innerHTML = `
            <label for="volume">Volume: </label>
            <input type="range" id="volume" min="0" max="1" step="0.1" value="${this.audio.volume}">
        `;
        stationList.appendChild(volumeControl);

        // Add station buttons
        this.stations.forEach((station, index) => {
            const button = document.createElement('button');
            button.className = 'station-button';
            // Use WebAssembly function to get station info if available
            const stationInfo = typeof Module !== 'undefined' ? 
                Module.getStationInfo(index) : 
                `${station.name} (${station.location})`;
            button.textContent = stationInfo;
            button.onclick = () => this.playStation(index);
            stationList.appendChild(button);
        });

        // Setup volume control
        const volumeSlider = document.getElementById('volume');
        if (volumeSlider) {
            volumeSlider.addEventListener('input', (e) => {
                this.audio.volume = e.target.value;
            });
        }
    }

    setupEventListeners() {
        this.audio.addEventListener('error', (e) => {
            console.error('Audio error:', e);
            const errorMessage = this.getErrorMessage(e);
            this.updateCurrentSong(errorMessage);
        });

        this.audio.addEventListener('playing', () => {
            this.updateCurrentSong(`Playing ${this.currentStation?.name || 'Unknown'}`);
        });

        this.audio.addEventListener('waiting', () => {
            this.updateCurrentSong('Buffering...');
        });

        this.audio.addEventListener('stalled', () => {
            this.updateCurrentSong('Stream stalled. Trying to reconnect...');
        });
    }

    getErrorMessage(error) {
        if (!this.currentStation) return 'Error: No station selected';
        
        if (error.target.error) {
            switch (error.target.error.code) {
                case error.target.error.MEDIA_ERR_ABORTED:
                    return 'Playback aborted by user';
                case error.target.error.MEDIA_ERR_NETWORK:
                    return 'Network error. Please check your connection';
                case error.target.error.MEDIA_ERR_DECODE:
                    return 'Stream format not supported by your browser';
                case error.target.error.MEDIA_ERR_SRC_NOT_SUPPORTED:
                    return 'Stream format not supported or station offline';
                default:
                    return 'Unknown error occurred';
            }
        }
        
        return `Error playing ${this.currentStation.name}. Please try another station.`;
    }

    playStation(index) {
        const station = this.stations[index];
        if (!station) {
            console.error('Invalid station index:', index);
            return;
        }
        
        // Stop current playback
        this.audio.pause();
        if (this.timeUpdateInterval) clearInterval(this.timeUpdateInterval);
        if (this.metadataInterval) clearInterval(this.metadataInterval);
        
        // Update UI
        document.querySelectorAll('.station-button').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.station-button')[index].classList.add('active');
        
        // Start new playback
        this.currentStation = station;
        this.updateCurrentSong(`Connecting to ${station.name}...`);
        
        // Create a new Audio element for each playback to avoid caching issues
        this.audio = new Audio();
        this.setupEventListeners();
        
        // Use WebAssembly function to get station URL if available
        const stationUrl = typeof Module !== 'undefined' ? 
            Module.getStationUrl(index) : 
            station.url;
            
        this.audio.src = stationUrl;
        
        // Add a timeout to handle connection issues
        const playPromise = this.audio.play();
        if (playPromise) {
            playPromise.catch(error => {
                console.error('Playback error:', error);
                this.updateCurrentSong(this.getErrorMessage({ target: { error } }));
            });
        }
        
        // Start time updates using WebAssembly
        this.timeUpdateInterval = setInterval(() => {
            if (typeof Module !== 'undefined') {
                const time = Module.getStationTime(index);
                document.getElementById('station-time').textContent = 
                    `[${station.name}] Local Time: ${time}`;
            } else {
                // Fallback to JavaScript time calculation
                const now = new Date();
                const utcTime = now.getTime() + (now.getTimezoneOffset() * 60000);
                const stationTime = new Date(utcTime + (station.utcOffset * 3600000));
                document.getElementById('station-time').textContent = 
                    `[${station.name}] Local Time: ${stationTime.toLocaleTimeString()}`;
            }
        }, 1000);
    }

    updateCurrentSong(title) {
        const songElement = document.getElementById('current-song');
        if (songElement) {
            songElement.textContent = title;
        }
    }
}

// Initialize the radio player when the page loads
window.addEventListener('load', () => {
    window.radioPlayer = new RadioPlayer();
});
