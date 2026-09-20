#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

int main(int count, char** words) {
  // The program is named for the application ID, so desktops match the
  // running app to its .desktop file rather than only to its binary.
  g_set_prgname(APPLICATION_ID);
  g_autoptr(GtkApplication) application =
      gtk_application_new(APPLICATION_ID, G_APPLICATION_NON_UNIQUE);

  // Everything after the program's own name goes to Dart.
  g_auto(GStrv) arguments = g_strdupv(words + 1);

  g_signal_connect(
      application, "activate",
      G_CALLBACK(+[](GApplication* application, gpointer data) {
        GtkWindow* window = GTK_WINDOW(
            gtk_application_window_new(GTK_APPLICATION(application)));

        // GNOME's header bar where GNOME runs, or on Wayland; elsewhere on X
        // a plain title bar, for window managers with layouts of their own.
        gboolean header = TRUE;
#ifdef GDK_WINDOWING_X11
        GdkScreen* screen = gtk_window_get_screen(window);
        if (GDK_IS_X11_SCREEN(screen) &&
            g_strcmp0(gdk_x11_screen_get_window_manager_name(screen),
                      "GNOME Shell") != 0) {
          header = FALSE;
        }
#endif
        if (header) {
          GtkHeaderBar* bar = GTK_HEADER_BAR(gtk_header_bar_new());
          gtk_widget_show(GTK_WIDGET(bar));
          gtk_header_bar_set_title(bar, "zephyron");
          gtk_header_bar_set_show_close_button(bar, TRUE);
          gtk_window_set_titlebar(window, GTK_WIDGET(bar));
        } else {
          gtk_window_set_title(window, "zephyron");
        }
        gtk_window_set_default_size(window, 1280, 720);

        g_autoptr(FlDartProject) project = fl_dart_project_new();
        fl_dart_project_set_dart_entrypoint_arguments(
            project, static_cast<char**>(data));

        FlView* view = fl_view_new(project);
        GdkRGBA background;
        gdk_rgba_parse(&background, "#000000");
        fl_view_set_background_color(view, &background);
        gtk_widget_show(GTK_WIDGET(view));
        gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

        // The window shows once Flutter draws, which needs the view realized.
        g_signal_connect(view, "first-frame",
                         G_CALLBACK(+[](FlView* view, gpointer) {
                           gtk_widget_show(
                               gtk_widget_get_toplevel(GTK_WIDGET(view)));
                         }),
                         nullptr);
        gtk_widget_realize(GTK_WIDGET(view));

        fl_register_plugins(FL_PLUGIN_REGISTRY(view));
        gtk_widget_grab_focus(GTK_WIDGET(view));
      }),
      arguments);

  // GApplication sees only the program's name, so it neither takes Dart's
  // arguments for options of its own nor refuses them.
  return g_application_run(G_APPLICATION(application), 1, words);
}
