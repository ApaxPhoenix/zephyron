#include "window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

// Redefined for Windows SDKs older than 10.0.22000.0.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

namespace {

constexpr const wchar_t kind[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

}  // namespace

Window::Window(const flutter::DartProject& source) : project(source) {}

Window::~Window() {
  controller = nullptr;
  if (handle) {
    DestroyWindow(handle);
    handle = nullptr;
  }
  UnregisterClass(kind, nullptr);
}

bool Window::Create(const std::wstring& title, int x, int y, int width,
                    int height) {
  WNDCLASS form{};
  form.hCursor = LoadCursor(nullptr, IDC_ARROW);
  form.lpszClassName = kind;
  form.style = CS_HREDRAW | CS_VREDRAW;
  form.hInstance = GetModuleHandle(nullptr);
  form.hIcon = LoadIcon(form.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
  form.lpfnWndProc = Window::Procedure;
  RegisterClass(&form);

  const POINT corner = {static_cast<LONG>(x), static_cast<LONG>(y)};
  const double scale = FlutterDesktopGetDpiForMonitor(MonitorFromPoint(
                           corner, MONITOR_DEFAULTTONEAREST)) /
                       96.0;
  if (!CreateWindow(kind, title.c_str(), WS_OVERLAPPEDWINDOW,
                    static_cast<int>(x * scale), static_cast<int>(y * scale),
                    static_cast<int>(width * scale),
                    static_cast<int>(height * scale), nullptr, nullptr,
                    GetModuleHandle(nullptr), this)) {
    return false;
  }
  Theme(handle);

  RECT area;
  GetClientRect(handle, &area);
  // The view starts at the window's own size, so no surface is made and
  // thrown away on the way up.
  controller = std::make_unique<flutter::FlutterViewController>(
      area.right - area.left, area.bottom - area.top, project);
  if (!controller->engine() || !controller->view()) {
    return false;
  }
  RegisterPlugins(controller->engine());
  content = controller->view()->GetNativeWindow();
  SetParent(content, handle);
  MoveWindow(content, area.left, area.top, area.right - area.left,
             area.bottom - area.top, true);
  SetFocus(content);

  controller->engine()->SetNextFrameCallback(
      [&]() { ShowWindow(handle, SW_SHOWNORMAL); });
  // Flutter can finish its first frame before the callback above is set;
  // this keeps a frame pending so the window shows either way.
  controller->ForceRedraw();
  return true;
}

LRESULT CALLBACK Window::Procedure(HWND const window, UINT const message,
                                   WPARAM const word,
                                   LPARAM const data) noexcept {
  if (message == WM_NCCREATE) {
    auto creation = reinterpret_cast<CREATESTRUCT*>(data);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
    // Scales the title bar and borders with the monitor's DPI, which only
    // per-monitor V1 awareness needs asking for.
    if (HMODULE user = LoadLibraryA("User32.dll")) {
      using Scaling = BOOL __stdcall(HWND);
      if (auto enable = reinterpret_cast<Scaling*>(
              GetProcAddress(user, "EnableNonClientDpiScaling"))) {
        enable(window);
      }
      FreeLibrary(user);
    }
    static_cast<Window*>(creation->lpCreateParams)->handle = window;
  } else if (auto that = reinterpret_cast<Window*>(
                 GetWindowLongPtr(window, GWLP_USERDATA))) {
    return that->Receive(window, message, word, data);
  }
  return DefWindowProc(window, message, word, data);
}

LRESULT Window::Receive(HWND const window, UINT const message,
                        WPARAM const word, LPARAM const data) noexcept {
  // Flutter, plugins included, sees every message first.
  if (controller) {
    if (std::optional<LRESULT> result = controller->HandleTopLevelWindowProc(
            window, message, word, data)) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (controller) {
        controller->engine()->ReloadSystemFonts();
      }
      break;

    case WM_DESTROY:
      handle = nullptr;
      controller = nullptr;
      PostQuitMessage(0);
      return 0;

    case WM_DPICHANGED: {
      auto bounds = reinterpret_cast<RECT*>(data);
      SetWindowPos(window, nullptr, bounds->left, bounds->top,
                   bounds->right - bounds->left, bounds->bottom - bounds->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }

    case WM_SIZE: {
      RECT area;
      GetClientRect(handle, &area);
      if (content) {
        MoveWindow(content, area.left, area.top, area.right - area.left,
                   area.bottom - area.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (content) {
        SetFocus(content);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      Theme(window);
      return 0;
  }

  return DefWindowProc(handle, message, word, data);
}

void Window::Theme(HWND const window) {
  // 0 asks apps for dark mode; anything else, or nothing, for light.
  DWORD light;
  DWORD size = sizeof(light);
  if (RegGetValue(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
          L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light,
          &size) == ERROR_SUCCESS) {
    BOOL dark = light == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                          sizeof(dark));
  }
}
