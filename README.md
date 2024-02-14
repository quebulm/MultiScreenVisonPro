# VisionPro Display Extender README
<a href="https://ibb.co/Kwkhm5c"><img src="https://i.ibb.co/wsXgYdZ/Bildschirmfoto-2024-02-14-um-04-35-54.png" alt="Bildschirmfoto-2024-02-14-um-04-35-54" border="0" /></a>
## Project Description
This project enables extending a Mac's display to multiple screens using VisionPro, bypassing the standard limitation of a single external display. It includes a Mac application for creating and streaming virtual displays to VisionPro, and an application on VisionPro for managing these displays, facilitating a wider desktop experience across multiple screens.

## How to Use

### Vision Pro App
1. **Start the Vision Pro app**: Ensure it's operational before launching the Mac app.
2. **Press 'Start Listening'**: Allows the app to receive display streams from the Mac.
3. **Press 'Extend Display'**: Opens a new window for using additional screens, supporting up to three.

### Mac App
1. **Launch the Mac app**: Proceed after the Vision Pro app is ready.
2. **Connection**: The Mac app automatically connects to Vision Pro and begins streaming the display once the Vision Pro app is in listening mode and the extend display feature is engaged. (Both must be on localhost for now)

## TODO
- **Improve Streaming Efficiency**: Currently using JPEG compression for the video stream over TCP. Consider switching to H.265 encoding or similar for better efficiency.
- **Display Size Synchronization**: Implement functionality to share display size information between VisionOS and Mac to ensure proper scaling.
- **User Interface Enhancements**: Develop a more intuitive and user-friendly interface.

### Current Status
This project is at the proof of concept stage. It can demonstrate the extended display functionality but may experience lag and is limited in features. Work is ongoing...
