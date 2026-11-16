/*
 * Added for remote_android_device_support (not part of upstream Headwind Remote).
 * Licensed under the Apache License, Version 2.0.
 */

package com.hmdm.control;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import com.hmdm.IMdmApi;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Optional link to the Headwind MDM launcher (when the device is enrolled):
 *  - reads this app's connection settings from the MDM's "Application settings",
 *    so nobody has to type the server URL or secret on the device;
 *  - reports the current session ID and PIN to the MDM (a device log line, and a
 *    device custom field), so support staff see them in the MDM panel.
 * Without the MDM every call quietly does nothing and the app works as before.
 */
public class MdmBridge {

    // Application settings read from the MDM (set them for this app's package).
    public static final String PREF_SERVER_URL = "server_url";
    public static final String PREF_SECRET = "secret";
    public static final String PREF_DEVICE_NAME = "device_name";
    public static final String PREF_IDLE_TIMEOUT = "idle_timeout";   // seconds, 0 = never exit
    public static final String PREF_SESSION_FIELD = "session_field"; // custom field 1-3, 0 = off

    private static final String SERVICE_ACTION = "com.hmdm.action.Connect";
    private static final String[] MDM_PACKAGES = {"com.hmdm.launcher", "ru.headwind.kiosk"};
    private static final long BIND_TIMEOUT_MS = 3000;
    private static final int DEFAULT_SESSION_FIELD = 1;
    private static final int LOG_INFO = 3; // Headwind log levels: 1 error ... 5 verbose

    private static final ExecutorService executor = Executors.newSingleThreadExecutor();
    private static final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static volatile IMdmApi api; // set on the main thread, read on the executor
    private static boolean bound;

    private static final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            api = IMdmApi.Stub.asInterface(service);
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            api = null;
        }
    };

    public interface SyncCallback {
        /** Runs on the main thread. changed: the connection settings differ from before. */
        void onSynced(boolean managed, boolean changed);
    }

    /** Copies the MDM's settings for this app into SettingsHelper (in the background). */
    public static void syncSettings(final Context context, final SyncCallback callback) {
        final Context app = context.getApplicationContext();
        executor.execute(() -> {
            boolean managed = false;
            boolean changed = false;
            IMdmApi mdm = getApi(app);
            if (mdm != null) {
                try {
                    changed = applySettings(app, mdm);
                    managed = true;
                } catch (Exception e) {
                    Log.w(Const.LOG_TAG, "MDM settings unavailable: " + e);
                    api = null;
                }
            }
            final boolean m = managed, c = changed;
            mainHandler.post(() -> callback.onSynced(m, c));
        });
    }

    private static boolean applySettings(Context context, IMdmApi mdm) throws Exception {
        SettingsHelper settings = SettingsHelper.getInstance(context);
        String pkg = context.getPackageName();
        boolean changed = false;

        String url = clean(mdm.queryAppPreference(pkg, PREF_SERVER_URL));
        if (url != null && url.startsWith("https://")) {
            changed |= update(settings, SettingsHelper.KEY_SERVER_URL, url);
            settings.setBoolean(SettingsHelper.KEY_USE_DEFAULT, false);
        }
        String secret = clean(mdm.queryAppPreference(pkg, PREF_SECRET));
        if (secret != null) {
            changed |= update(settings, SettingsHelper.KEY_SECRET, secret);
        }
        // Name shown to support staff: the MDM setting, else the MDM device number.
        String name = clean(mdm.queryAppPreference(pkg, PREF_DEVICE_NAME));
        if (name == null) {
            Bundle config = mdm.queryConfig();
            name = config != null ? clean(config.getString("DEVICE_ID")) : null;
        }
        if (name != null) {
            changed |= update(settings, SettingsHelper.KEY_DEVICE_NAME, name);
        }
        Integer idle = parseInt(mdm.queryAppPreference(pkg, PREF_IDLE_TIMEOUT));
        if (idle != null && idle >= 0) {
            // 0 is "never" in the app, but SettingsHelper uses 0 for "unset"; -1 means never.
            settings.setInt(SettingsHelper.KEY_IDLE_TIMEOUT, idle == 0 ? -1 : idle);
        }
        return changed;
    }

    /** Publishes "session ID / PIN / link" to the MDM; text null clears the field. */
    public static void reportSession(final Context context, final String text) {
        final Context app = context.getApplicationContext();
        executor.execute(() -> {
            IMdmApi mdm = getApi(app);
            if (mdm == null) {
                return;
            }
            try {
                String pkg = app.getPackageName();
                Integer field = parseInt(mdm.queryAppPreference(pkg, PREF_SESSION_FIELD));
                int number = field != null ? field : DEFAULT_SESSION_FIELD;
                if (number >= 1 && number <= 3) {
                    // Uploaded with the next device info (at most 15 minutes later).
                    mdm.setCustom(number, text != null ? text : "");
                }
                // Device log lines are uploaded right away (needs a Device Log rule).
                mdm.log(System.currentTimeMillis(), LOG_INFO, pkg,
                        text != null ? "Remote support ready: " + text : "Remote support closed");
            } catch (Exception e) {
                Log.w(Const.LOG_TAG, "MDM report failed: " + e);
                api = null;
            }
        });
    }

    /** Waits (up to BIND_TIMEOUT_MS) for the launcher's API; null if it isn't installed. */
    private static IMdmApi getApi(Context context) {
        if (api != null) {
            return api;
        }
        if (bound) {
            // A previous binding died; rebind from scratch.
            try {
                context.unbindService(connection);
            } catch (Exception e) {
            }
            bound = false;
        }
        for (String pkg : MDM_PACKAGES) {
            try {
                Intent intent = new Intent(SERVICE_ACTION).setPackage(pkg);
                if (context.bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
                    bound = true;
                    break;
                }
            } catch (SecurityException e) {
                // Not allowed; try the next package
            }
        }
        if (!bound) {
            return null;
        }
        // onServiceConnected runs on the main thread; this runs on the executor.
        long deadline = System.currentTimeMillis() + BIND_TIMEOUT_MS;
        while (api == null && System.currentTimeMillis() < deadline) {
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                break;
            }
        }
        return api;
    }

    private static boolean update(SettingsHelper settings, String key, String value) {
        if (value.equals(settings.getString(key))) {
            return false;
        }
        settings.setString(key, value);
        return true;
    }

    /** Trims and drops control characters (a typed Enter broke the textroom join). */
    static String clean(String value) {
        if (value == null) {
            return null;
        }
        String result = value.replaceAll("\\p{Cntrl}", " ").trim();
        return result.isEmpty() ? null : result;
    }

    private static Integer parseInt(String value) {
        try {
            return value != null ? Integer.valueOf(value.trim()) : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
