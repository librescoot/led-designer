# LibreScoot LED Designer

[![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]

A modern Flutter application for designing and programming LED light patterns and cues for electric scooters. This tool allows users to create, edit, and export LED animations and patterns with an intuitive graphical interface.

## Features

- 🎨 Visual LED fade curve designer
- 📋 Cue management system for organizing LED patterns
- 📦 Export functionality for binary files
- 📱 Cross-platform support (Windows, macOS, Linux)
- 🎯 Real-time preview of LED animations
- 💾 Save and load project files

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Git

### Installation

1. Clone the repository:
```bash
git clone https://github.com/librescoot/led-designer.git
cd led-designer
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the application:
```bash
flutter run
```

## Usage

1. **Creating Fades**
   - Use the fade editor to design LED transition patterns
   - Adjust timing and intensity using the visual curve editor
   - Preview your fades in real-time

2. **Managing Cues**
   - Create and organize LED cues
   - Combine multiple fades into complex sequences
   - Save frequently used patterns as predefined cues

3. **Exporting**
   - Export your designs in binary format
   - Compatible with LibreScoot firmware
   - Save projects for future editing

## Development

This project is built with Flutter and uses several key dependencies:
- `fl_chart`: For fade curve visualization
- `provider`: State management
- `path_provider`: File operations
- `file_picker`: File/directory selection
- `json_annotation`: Data serialization

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg

## Support

For support, please open an issue in the GitHub repository or contact the maintainers.

---

Made with ❤️ by the LibreScoot community