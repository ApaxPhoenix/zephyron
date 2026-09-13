#include <flutter/dart_project.h>
#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

#include "window.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous,
                      _In_ wchar_t* line, _In_ int show) {
  // Writes to the console there is, as under `flutter run`, or to a new one
  // under a debugger, from the runner and the Flutter library alike.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent() &&
      ::AllocConsole()) {
    FILE* unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }

  // COM, for the library and plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // The command line in UTF-8 for the engine, without the program's name.
  std::vector<std::string> arguments;
  int count = 0;
  if (wchar_t** words = ::CommandLineToArgvW(::GetCommandLineW(), &count)) {
    for (int index = 1; index < count; index++) {
      int length = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                         words[index], -1, nullptr, 0,
                                         nullptr, nullptr);
      std::string text(length > 0 ? length : 1, '\0');
      if (length > 0) {
        ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, words[index], -1,
                              text.data(), length, nullptr, nullptr);
      }
      text.resize(length > 0 ? length - 1 : 0);
      arguments.push_back(text);
    }
    ::LocalFree(words);
  }
  project.set_dart_entrypoint_arguments(std::move(arguments));

  Window window(project);
  if (!window.Create(L"zephyron", 10, 10, 1280, 720)) {
    return EXIT_FAILURE;
  }

  ::MSG message;
  while (::GetMessage(&message, nullptr, 0, 0)) {
    ::TranslateMessage(&message);
    ::DispatchMessage(&message);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
