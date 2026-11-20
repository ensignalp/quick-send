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

static void platform_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "isWayland") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(GPOINTER_TO_INT(user_data))));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// ---------------------------------------------------------------------------
// GNOME window.
//
// The title bar follows the operating system: the GTK theme, icon theme and
// button layout come from the desktop settings (e.g. Breeze-Dark + breeze
// icons), and light/dark from org.gnome.desktop.interface color-scheme, the
// way GNOME's own apps follow it. Nothing is drawn by the app.
//
// One compatibility fix: theme tools (e.g. rewaita) write title button rules
// into ~/.config/gtk-3.0/gtk.css that are meant for GTK4/libadwaita (colours by
// names GTK3 does not resolve, icons set to transparent). In a GTK3 window they
// leave the minimize/maximize/close buttons invisible or visible only on hover.
// Only when that stylesheet styles title buttons, the colour, background and
// transparency it puts on them are undone at a priority just above it; the
// buttons then show the system icon theme's window-*-symbolic icons (e.g.
// breeze) in the theme's header colour. Nothing is drawn by the app, and
// without such a stylesheet the theme is left completely alone.
// ---------------------------------------------------------------------------

static const char* kQsTitleButtonCss =
    "headerbar button.titlebutton, .titlebar button.titlebutton {\n"
    "  background-image: none; background-color: transparent; color: @theme_fg_color;\n"
    "  box-shadow: none; border: none; min-width: 24px; min-height: 24px; padding: 2px; opacity: 1;\n"
    "}\n"
    "headerbar button.titlebutton:hover, .titlebar button.titlebutton:hover {\n"
    "  background-color: alpha(@theme_fg_color, 0.12);\n"
    "}\n"
    "headerbar button.titlebutton > image, .titlebar button.titlebutton > image {\n"
    "  color: inherit; opacity: 1; -gtk-icon-transform: none; -gtk-icon-shadow: none;\n"
    "}\n";

// True when the user stylesheet has its own title button rules (see above).
static gboolean qs_user_css_styles_title_buttons() {
  g_autofree gchar* path = g_build_filename(g_get_user_config_dir(), "gtk-3.0", "gtk.css", nullptr);
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(path, &contents, nullptr, nullptr)) return FALSE;
  return strstr(contents, "titlebutton") != nullptr;
}

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

// Light/dark as the desktop's colour scheme says (GTK3 does not read color-scheme by itself).
static void qs_apply_brightness() {
  gboolean dark = FALSE;
  if (qs_interface_settings != nullptr) {
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
  g_warning("Quick Send compatibility CSS: %s", error->message);
}

static void qs_apply_gnome_look() {
  static GSettings* wm_settings = nullptr;
  static GtkCssProvider* provider = nullptr;
  if (provider != nullptr) return;

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
  if (qs_user_css_styles_title_buttons()) {
    g_signal_connect(provider, "parsing-error", G_CALLBACK(qs_css_error), nullptr);
    gtk_css_provider_load_from_data(provider, kQsTitleButtonCss, -1, nullptr);
    // Just above the user stylesheet, whose title button rules it undoes.
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
                                              GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
    g_debug("Quick Send: user stylesheet title button rules neutralised");
  }
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

  // GNOME: a GtkHeaderBar in the system theme (see "GNOME window" above). Elsewhere: honour GTK_CSD=1, else
  // let the desktop draw its own decorations.
  const char* GTK_CSD = getenv("GTK_CSD");
  const bool gnome = qs_is_gnome();
  if (gnome || (GTK_CSD && strcmp(GTK_CSD, "1") == 0)) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Quick Send");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
        gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Quick Send");
  }
  if (gnome) {
    qs_apply_gnome_look();
  }

  gtk_window_set_default_size(window, 575, 770);

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
