#ifndef RUNNER_WINDOW_H_
#define RUNNER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <memory>
#include <string>

// A high-DPI aware window that hosts the Flutter view and quits the app when
// it closes.
class Window {
 public:
  explicit Window(const flutter::DartProject& source);
  ~Window();

  // Opens the window titled |title| at |x|, |y|, |width| by |height| logical
  // pixels, scaled for the monitor it opens on. It stays hidden until
  // Flutter has drawn its first frame.
  bool Create(const std::wstring& title, int x, int y, int width, int height);

 private:
  // The system's callback for every message the window gets.
  static LRESULT CALLBACK Procedure(HWND const window, UINT const message,
                                    WPARAM const word,
                                    LPARAM const data) noexcept;

  LRESULT Receive(HWND const window, UINT const message, WPARAM const word,
                  LPARAM const data) noexcept;

  // Matches the frame's light or dark look to the system's.
  static void Theme(HWND const window);

  flutter::DartProject project;
  std::unique_ptr<flutter::FlutterViewController> controller;
  HWND handle = nullptr;
  HWND content = nullptr;
};

#endif  // RUNNER_WINDOW_H_
