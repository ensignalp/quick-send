#include "my_application.h"

#include <cstddef>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <stdlib.h>
#include <string.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Title bar brightness requested by the app theme (-1: none yet, follow the desktop).
static int qs_dark_override = -1;
static void qs_apply_brightness();

static void platform_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "isWayland") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(GPOINTER_TO_INT(user_data))));
  } else if (strcmp(fl_method_call_get_name(method_call), "setTitleBarDark") == 0) {
    // Quick Send: the title bar follows the app's light/dark theme.
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
      qs_dark_override = fl_value_get_bool(args) ? 1 : 0;
      qs_apply_brightness();
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// ---------------------------------------------------------------------------
// GNOME look.
//
// GNOME's own apps are GTK4/libadwaita and ignore ~/.config/gtk-3.0. A GTK3 app
// like this one inherits the GTK3 theme and every rule of
// ~/.config/gtk-3.0/gtk.css instead. Theming tools write title button rules
// there that can leave the minimize/maximize icons transparent until hovered
// (e.g. colours referencing an undefined @window-fg-color). On GNOME the window
// therefore uses Adwaita, light or dark with the app theme (desktop color-scheme until the app reports it), and
// gets libadwaita-style window controls from a provider that sits above the
// user stylesheet (GTK3 resolves provider priority before selector specificity).
// ---------------------------------------------------------------------------

static const char* kQsGnomeCss =
    "headerbar.qs-headerbar { min-height: 46px; padding: 0 6px; }\n"
    "headerbar.qs-headerbar .title { font-weight: bold; }\n"
    "button.titlebutton {\n"
    "  min-width: 24px; min-height: 24px; padding: 0; margin: 0 4px;\n"
    "  border: none; border-radius: 9999px; box-shadow: none; outline: none;\n"
    "  background-color: alpha(currentColor, 0.1); background-image: none;\n"
    "  color: inherit; opacity: 1; -gtk-icon-shadow: none; -gtk-icon-transform: none;\n"
    "}\n"
    "button.titlebutton:hover { background-color: alpha(currentColor, 0.15); }\n"
    "button.titlebutton:active { background-color: alpha(currentColor, 0.3); }\n"
    "button.titlebutton:backdrop { opacity: 0.7; }\n"
    "button.titlebutton > image {\n"
    "  color: inherit; opacity: 1; padding: 0; margin: 0; min-width: 16px; min-height: 16px;\n"
    "  -gtk-icon-shadow: none; -gtk-icon-transform: none;\n"
    "}\n";

static gboolean qs_is_gnome() {
  const char* desktop = getenv("XDG_CURRENT_DESKTOP");
  return desktop != nullptr && strstr(desktop, "GNOME") != nullptr;
}

static GSettings* qs_settings_if_has_key(const char* schema_id, const char* key) {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  if (source == nullptr) return nullptr;
  g_autoptr(GSettingsSchema) schema = g_settings_schema_source_lookup(source, schema_id, TRUE);
  if (schema == nullptr || !g_settings_schema_has_key(schema, key)) return nullptr;
  return g_settings_new(schema_id);
}

static GSettings* qs_interface_settings = nullptr;

// Dark title bar when the app theme is dark; before the app reports its theme, the desktop's colour scheme.
static void qs_apply_brightness() {
  gboolean dark = FALSE;
  if (qs_dark_override >= 0) {
    dark = qs_dark_override == 1;
  } else if (qs_interface_settings != nullptr) {
    g_autofree gchar* scheme = g_settings_get_string(qs_interface_settings, "color-scheme");
    dark = g_strcmp0(scheme, "prefer-dark") == 0;
  }
  g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", dark, nullptr);
}

static void qs_sync_color_scheme(GSettings* settings, const gchar* key, gpointer user_data) {
  qs_apply_brightness();
}

static void qs_sync_button_layout(GSettings* settings, const gchar* key, gpointer user_data) {
  g_autofree gchar* layout = g_settings_get_string(settings, "button-layout");
  g_object_set(gtk_settings_get_default(), "gtk-decoration-layout", layout, nullptr);
}

static void qs_css_error(GtkCssProvider* provider, GtkCssSection* section, GError* error, gpointer user_data) {
  g_warning("Quick Send header bar CSS: %s", error->message);
}

static void qs_apply_gnome_look() {
  static GSettings* wm_settings = nullptr;
  static GtkCssProvider* provider = nullptr;
  if (provider != nullptr) return;

  g_object_set(gtk_settings_get_default(), "gtk-theme-name", "Adwaita", "gtk-icon-theme-name", "Adwaita", nullptr);

  qs_interface_settings = qs_settings_if_has_key("org.gnome.desktop.interface", "color-scheme");
  if (qs_interface_settings != nullptr) {
    g_signal_connect(qs_interface_settings, "changed::color-scheme", G_CALLBACK(qs_sync_color_scheme), nullptr);
  }
  qs_apply_brightness();
  wm_settings = qs_settings_if_has_key("org.gnome.desktop.wm.preferences", "button-layout");
  if (wm_settings != nullptr) {
    qs_sync_button_layout(wm_settings, nullptr, nullptr);
    g_signal_connect(wm_settings, "changed::button-layout", G_CALLBACK(qs_sync_button_layout), nullptr);
  }

  provider = gtk_css_provider_new();
  g_signal_connect(provider, "parsing-error", G_CALLBACK(qs_css_error), nullptr);
  gtk_css_provider_load_from_data(provider, kQsGnomeCss, -1, nullptr);
  gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
                                            GTK_STYLE_PROVIDER_PRIORITY_USER + 100);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Start hidden with --hidden, and (Quick Send) in the tray like init.dart does: no --show and
  // no file arguments. The window is then only realized, never mapped. Mapping it and letting Dart
  // hide it before the first frame would stop Flutter from building the home page, so the receive
  // server (started from there) would not run until the window is opened.
  bool start_hidden = false;
  bool show_requested = false;
  bool has_files = false;
  if (self->dart_entrypoint_arguments != nullptr) {
    for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; i++) {
      const char* arg = self->dart_entrypoint_arguments[i];
      if (strcmp(arg, "--hidden") == 0) {
        start_hidden = true;
      } else if (strcmp(arg, "--show") == 0) {
        show_requested = true;
      } else if (arg[0] != '-') {
        has_files = true;
      }
    }
  }
  if (!show_requested && !has_files) {
    start_hidden = true;
  }

  // GNOME: a real GtkHeaderBar styled like libadwaita, light or dark with the app
  // theme (setTitleBarDark; the desktop colour scheme until the app reports it). Elsewhere: honour GTK_CSD=1, else
  // let the desktop draw its own decorations.
  const char* GTK_CSD = getenv("GTK_CSD");
  const bool gnome = qs_is_gnome();
  if (gnome || (GTK_CSD && strcmp(GTK_CSD, "1") == 0)) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Quick Send");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(header_bar)), "qs-headerbar");
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Quick Send");
  }
  if (gnome) {
    qs_apply_gnome_look();
  }

  gtk_window_set_default_size(window, 900, 500);

  // Window icon. X11 docks and window switchers use it when no desktop entry
  // matches the window; on Wayland the compositor resolves the app id
  // (APPLICATION_ID) to the installed .desktop file and theme icon instead.
  gtk_window_set_icon_name(window, APPLICATION_ID);
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "flutter_assets", "assets", "img", "logo-256.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }

  if (!start_hidden) {
    gtk_widget_show(GTK_WIDGET(window));
  } else {
    // Realize the window so plugins (like tray) can initialize, 
    // but don't map it to the screen.
    gtk_widget_realize(GTK_WIDGET(window));
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) platform_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "org.localsend.localsend_app/platform", FL_METHOD_CODEC(codec));
  bool is_wayland = false;
#ifdef GDK_WINDOWING_WAYLAND
  is_wayland = GDK_IS_WAYLAND_DISPLAY(
      gtk_widget_get_display(GTK_WIDGET(window)));
#endif
  fl_method_channel_set_method_call_handler(
      platform_channel, platform_method_call_cb, GINT_TO_POINTER(is_wayland),
      nullptr);

  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  if (!start_hidden) {
    gtk_widget_grab_focus(GTK_WIDGET(view));
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
