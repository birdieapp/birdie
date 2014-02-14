// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2013-2014 Birdie Developers (http://birdieapp.github.io)
 *
 * This software is licensed under the GNU General Public License
 * (version 3 or later). See the COPYING file in this distribution.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this software; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Authored by: Ivo Nunes <ivoavnunes@gmail.com>
 *              Vasco Nunes <vascomfnunes@gmail.com>
 */

namespace Birdie.Widgets {
#if HAVE_GRANITE
    public class TweetDialog : Granite.Widgets.LightWindow {
#else
    public class TweetDialog : Gtk.Dialog {
#endif
        Gtk.Image avatar;
        Gtk.SourceView view;
        Gtk.Entry entry;
        Gtk.EntryCompletion entry_completion;
        Gtk.Label count_label;
        int count;
        Gtk.Button tweet;
        Gtk.Image file_chooser_btn_image;
        Gtk.FileChooserDialog file_chooser;
        Gtk.Button file_chooser_btn;
        bool tweet_disabled;
        Gtk.Button cancel;
        Gtk.TreeIter iter;
        Gtk.ListStore list_store;
        string id;
        string user_screen_name;
        string[] mentioned_users;
        bool dm;
        bool has_media;
        private string filler;
        private int count_remaining;
        private string virtual_text;
        private int opening_x;
        private int opening_y;
        private Regex urls;
        private string media_uri;

        Birdie birdie;

        private Gtk.Box container;

        public TweetDialog (Birdie birdie, string id = "",
            string user_screen_name = "", bool dm = false, string[] mentioned_users = {}) {

            this.birdie = birdie;
            this.id = id;
            this.user_screen_name = user_screen_name;
            this.dm = dm;
            this.deletable = false;
            this.count_remaining = 140;
            this.has_media = false;
            this.mentioned_users = mentioned_users;

            // connect signal to handle key events
            this.key_press_event.connect ((event) => {
                this.handle_key_events (this, event);
                return false;
            });

            if (!dm)
                this.set_title (_("New Tweet"));
            else
                this.set_title (_("New Message"));

#if HAVE_GRANITE
            this.box.foreach ((w) => {
                this.box.remove (w);
            });

            this.container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.box.add (container);
#else
            container = this.get_content_area ();
            set_resizable (false);
#endif

            this.media_uri = "";

            this.set_transient_for (birdie.m_window);
            this.set_modal (true);

            if (!this.birdie.m_window.get_visible ())
                this.set_keep_above (true);

            this.birdie.m_window.configure_event.connect ((w, e) => {
                if (this.birdie.m_window.get_visible ())
                    this.restore_window ();

                return true;
            });

            // restore dialog size and position
            this.opening_x = this.birdie.settings.get_int ("compose-opening-x");
            this.opening_y = this.birdie.settings.get_int ("compose-opening-y");

            this.avatar = new Gtk.Image ();
            this.avatar.set_from_file (Environment.get_home_dir () +
                "/.cache/birdie/" + this.birdie.api.account.profile_image_file);

            this.view = new Gtk.SourceView ();
            this.view.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
            this.view.set_size_request(300, 80);
            this.view.set_accepts_tab (false);

            var dm_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            this.entry = new Gtk.Entry ();
            this.entry_completion = new Gtk.EntryCompletion ();

            // usernames completion
            this.entry.set_completion (entry_completion);

            // Create and register a ListStore for completion
            this.list_store = new Gtk.ListStore (1, typeof (string), typeof (string));
            entry_completion.set_model (list_store);
            entry_completion.set_text_column (0);
            entry_completion.set_inline_completion (true);
            entry_completion.set_inline_selection (true);

            // fill ListStore from db
            foreach (string user in this.birdie.db.get_users (this.birdie.default_account_id)) {
                list_store.append (out iter);
                list_store.set (iter, 0, user);
            }

            view.completion.get_providers ().foreach ((p) => {
                try {
                    view.completion.remove_provider (p);
                } catch (Error e) {
                    warning (e.message);
                }
            });

            view.completion.accelerators = 0;

            var comp_provider = new CompletionProvider (this.view, this.birdie.default_account_id);
            comp_provider.priority = 1;
            comp_provider.name = _("Suggestions");

            try {
                this.view.completion.add_provider (comp_provider);
            } catch (Error e) {
                warning (e.message);
            }


            if (dm && user_screen_name == "") {
                this.entry.set_text ("@");
                this.entry.get_buffer ().inserted_text.connect (() => {
                    buffer_changed ();
                });

                this.entry.get_buffer ().deleted_text.connect (() => {
                    buffer_changed ();
                });

                dm_box.add (this.entry);
                dm_box.add (this.view);
            } else if (dm && user_screen_name != "") {
                this.set_title (_("New Message in reply to @") + user_screen_name);
            }

            if (!dm) {
                if (id != "" && user_screen_name != "") {
                    if ("@" in user_screen_name) {
                        this.view.buffer.insert_at_cursor (" " + user_screen_name, -1);

                        Gtk.TextIter start;
                        this.view.buffer.get_start_iter (out start);

                        this.view.buffer.place_cursor (start);
                    } else {
                        this.view.buffer.insert_at_cursor ("@" + user_screen_name + " ", -1);
                    }
                }

                foreach(string username in mentioned_users) {
                    this.view.buffer.insert_at_cursor (username + " ", -1);
                }
            }

            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var avatarbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            avatarbox.pack_start (this.avatar, false, false, 0);
            avatarbox.pack_start (new Gtk.Label (""), true, true, 0);
            avatarbox.margin_right = 12;
            top.add (avatarbox);
            if (dm && user_screen_name == "")
                top.add (dm_box);
            else
                top.add (this.view);
            top.margin = 12;

            this.view.buffer.changed.connect (() => {
                buffer_changed ();
            });

            this.tweet_disabled = true;
            this.count = this.count_remaining;
            this.count_label = new Gtk.Label (this.count.to_string ());
            this.count_label.set_markup ("<span color='#777777'>" + this.count.to_string () + "</span>");

            this.cancel = new Gtk.Button.with_label (_("Cancel"));
            this.cancel.set_size_request (100, -1);
            this.cancel.clicked.connect (() => {
                this.save_window ();
                this.destroy ();
            });

            if (dm)
                this.tweet = new Gtk.Button.with_label (_("Send"));
            else
                this.tweet = new Gtk.Button.with_label (_("Tweet"));
            this.tweet.set_size_request (100, -1);
            this.tweet.margin_left = 6;
            this.tweet.set_sensitive (false);

            this.tweet.clicked.connect (() => {
                new Thread<void*> (null, this.tweet_thread);
            });

            this.tweet.get_style_context().add_class ("suggested-action");

            this.file_chooser_btn = new Gtk.Button();
            this.file_chooser_btn.set_tooltip_text (_("Add a picture"));
            this.file_chooser_btn_image = new Gtk.Image.from_icon_name ("insert-image-symbolic", Gtk.IconSize.MENU);
            this.file_chooser_btn.set_image (this.file_chooser_btn_image);
            this.file_chooser_btn.set_relief (Gtk.ReliefStyle.NONE);
            this.file_chooser_btn.margin_right = 6;

            // Emitted when media icon is clicked
            file_chooser_btn.clicked.connect (() => {
                on_add_photo_clicked ();
            });

            Gtk.Box bottom = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            bottom.pack_start (this.count_label, false, false, 0);
            bottom.pack_start (new Gtk.Label (""), true, true, 0);
            bottom.pack_start (this.file_chooser_btn, false, false, 0);
            bottom.pack_start (this.cancel, false, false, 0);
            bottom.pack_start (this.tweet, false, false, 0);
            bottom.margin = 12;
            this.container.add (top);
            this.container.add (bottom);
            this.show_all ();
            this.buffer_changed ();
            this.restore_window ();
        }

        private void on_add_photo_clicked () {
            this.file_chooser = new Gtk.FileChooserDialog (_("Select a Picture"), this,
            Gtk.FileChooserAction.OPEN,
            _("Cancel"), Gtk.ResponseType.CANCEL,
            _("Open"), Gtk.ResponseType.OK);

            // filter to jpg, png and gif:
            Gtk.FileFilter filter = new Gtk.FileFilter ();
            this.file_chooser.set_filter (filter);
            filter.add_mime_type ("image/jpeg");
            filter.add_mime_type ("image/png");
            filter.add_mime_type ("image/gif");
            //

            // Add a preview widget:
            Gtk.Image preview_area = new Gtk.Image ();

            file_chooser.set_preview_widget (preview_area);
            file_chooser.update_preview.connect (() => {
                string uri = file_chooser.get_preview_uri ();
                // We only display local files:
                if (uri.has_prefix ("file://") == true) {
                    try {
                        Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file (uri.substring (7));
                        Gdk.Pixbuf scaled = pixbuf.scale_simple (150, 150, Gdk.InterpType.BILINEAR);
                        preview_area.set_from_pixbuf (scaled);
                        preview_area.show ();
                    } catch (Error e) {
                        preview_area.hide ();
                    }
                } else {
                    preview_area.hide ();
                }
            });

            if (this.file_chooser.run () == Gtk.ResponseType.OK) {
                SList<string> uris = file_chooser.get_uris ();
                foreach (unowned string uri in uris) {
                    this.media_uri = uri;
                }
                try {
                    Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file (this.file_chooser.get_filename ());
                    Gdk.Pixbuf scaled = pixbuf.scale_simple (16, 16, Gdk.InterpType.BILINEAR);
                    this.file_chooser_btn_image = new Gtk.Image.from_pixbuf (scaled);
                    this.file_chooser_btn.set_image (this.file_chooser_btn_image);
                    this.has_media = true;
                    buffer_changed ();
                } catch (Error e) {
                    preview_area.hide ();
                }
            }
            this.file_chooser.destroy ();
        }

        private void* tweet_thread () {
            Gtk.TextIter start;
            Gtk.TextIter end;

            this.view.buffer.get_start_iter (out start);
            this.view.buffer.get_end_iter (out end);

            if (dm && this.user_screen_name == "")
                this.user_screen_name = this.entry.get_text ();

            this.hide ();
            birdie.tweet_callback (this.view.buffer.get_text (start, end, false),
                this.id, this.user_screen_name, this.dm, this.media_uri);

            Idle.add (() => {
                this.save_window ();
                this.destroy ();
                return false;
            });

            return null;
        }

        private void buffer_changed () {
            Gtk.TextIter start;
            Gtk.TextIter end;

            if (this.has_media)
                this.count_remaining = 120;
            else
                this.count_remaining = 140;

            var tmp_entry = this.entry.get_text ();

            // a filler to fake virtual string controller with shortened urls
            this.filler = "0123456789012345678901";

            this.view.buffer.get_start_iter (out start);
            this.view.buffer.get_end_iter (out end);

            virtual_text = this.view.buffer.get_text (start, end, false);

            try {
                urls = new Regex("((https?://|ftp://|www.)([\\S]+))");
            } catch (RegexError e) {
                warning ("regex error: %s", e.message);
            }

            // replace urls with filler to fill them with 22 chars each
            try {
                virtual_text = urls.replace (virtual_text, -1, 0, filler);
            }
            catch (Error e) {
                warning ("url replacing error: %s", e.message);
            }

            this.count = this.count_remaining - virtual_text.char_count ();
            this.count_label.set_markup ("<span color='#777777'>" + this.count.to_string () + "</span>");

            if ((this.count < 0 || this.count >= 140) || (" " in tmp_entry && dm && this.entry.get_visible ()) || (this.entry.get_buffer ().length < 3 && dm && this.entry.get_visible ())) {
                // make remaining chars indicator red to warn user
                if (this.count < 0) {
                    this.count_label.set_markup ("<span color='#FF0000'>" + this.count.to_string () + "</span>");
                }
                this.tweet.set_sensitive (false);
                this.tweet_disabled = true;
            } else if (this.tweet_disabled) {
                this.tweet.set_sensitive (true);
                this.tweet_disabled = false;
            }
        }

        private void handle_key_events (Gtk.Widget source, Gdk.EventKey key) {
            // if Esc pressed, destroy dialog
            if (key.keyval == Gdk.Key.Escape) {
                Idle.add (() => {
                this.save_window ();
                this.destroy ();
                return false;
                });
            } else
              if (key.keyval == Gdk.Key.Tab) {
                //
            }
        }

        private void save_window () {
            if (!this.birdie.m_window.get_visible ()) {
                this.get_position (out opening_x, out opening_y);
                this.birdie.settings.set_int ("compose-opening-x", opening_x);
                this.birdie.settings.set_int ("compose-opening-y", opening_y);
            }
        }

        private void restore_window () {
            if (this.opening_x > 0 && this.opening_y > 0 && !this.birdie.m_window.get_visible ()) {
                this.move (this.opening_x, this.opening_y);
            } else if (this.birdie.m_window.get_visible ()) {
#if HAVE_GRANITE
                int x, y, sx, sy, tx, ty;

                this.birdie.m_window.get_position (out x, out y);
                this.birdie.m_window.get_size (out sx, out sy);
                this.get_size (out tx, out ty);

                this.move (x + sx / 2 - tx / 2, y + 60);
#endif
            }
        }

        public override bool button_press_event (Gdk.EventButton e) {
            if (this.birdie.m_window.get_visible ())
                return false;
            else
                return base.button_press_event (e);
        }
    }
}