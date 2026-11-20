package app.novelia.reader;

import android.app.Service;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.media.session.MediaSession;
import android.media.session.MediaController;
import android.app.PendingIntent;

public class NoveliaPlaybackService extends Service {
    public static final String ACTION_START = "app.novelia.reader.audio.START";
    public static final String ACTION_PAUSE = "app.novelia.reader.audio.PAUSE";
    public static final String ACTION_STOP = "app.novelia.reader.audio.STOP";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_TOKEN = "session_token";
    private static final String CHANNEL_ID = "novelia_audio";
    private static final int NOTIFICATION_ID = 4102;
    private MediaSession.Token sessionToken;
    private String currentTitle = "Novelia";
    private boolean playing = true;

    @Override public void onCreate() {
        super.onCreate();
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "Lecture audio Novelia", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Commandes de lecture audio");
            channel.setShowBadge(false);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || ACTION_STOP.equals(intent.getAction())) {
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        String title = intent.getStringExtra(EXTRA_TITLE);
        if (title != null && !title.trim().isEmpty()) currentTitle = title;
        MediaSession.Token token = intent.getParcelableExtra(EXTRA_TOKEN);
        if (token != null) sessionToken = token;

        String action = intent.getAction();
        if (ACTION_PAUSE.equals(action)) {
            playing = false;
        } else if (ACTION_START.equals(action)) {
            playing = true;
        } else if ("app.novelia.reader.audio.PREVIOUS".equals(action)
                || "app.novelia.reader.audio.PLAY_PAUSE".equals(action)
                || "app.novelia.reader.audio.NEXT".equals(action)) {
            dispatchTransportAction(action);
        }

        Notification notification = buildNotification();
        if (ACTION_START.equals(action)) {
            startForeground(NOTIFICATION_ID, notification);
        } else {
            getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, notification);
        }
        return START_NOT_STICKY;
    }

    private void dispatchTransportAction(String action) {
        if (sessionToken == null) return;
        try {
            MediaController.TransportControls controls =
                new MediaController(this, sessionToken).getTransportControls();
            if ("app.novelia.reader.audio.PREVIOUS".equals(action)) {
                controls.skipToPrevious();
            } else if ("app.novelia.reader.audio.NEXT".equals(action)) {
                controls.skipToNext();
            } else if (playing) {
                controls.pause();
            } else {
                controls.play();
            }
        } catch (RuntimeException ignored) {
        }
    }

    private PendingIntent serviceAction(String action, int requestCode) {
        Intent intent = new Intent(this, NoveliaPlaybackService.class);
        intent.setAction(action);
        intent.putExtra(EXTRA_TOKEN, sessionToken);
        intent.putExtra(EXTRA_TITLE, currentTitle);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getService(this, requestCode, intent, flags);
    }

    private Notification buildNotification() {
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID) : new Notification.Builder(this);
        builder.setContentTitle(currentTitle)
            .setContentText(playing ? "Lecture audio en cours" : "Lecture en pause")
            .setSmallIcon(playing ? android.R.drawable.ic_media_play : android.R.drawable.ic_media_pause)
            .setOngoing(playing)
            .setVisibility(Notification.VISIBILITY_PUBLIC);

        if (sessionToken != null && Build.VERSION.SDK_INT >= 21) {
            Notification.MediaStyle style = new Notification.MediaStyle().setMediaSession(sessionToken);
            builder.addAction(new Notification.Action.Builder(
                android.R.drawable.ic_media_previous, "Précédent",
                serviceAction("app.novelia.reader.audio.PREVIOUS", 4103)).build());
            builder.addAction(new Notification.Action.Builder(
                playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
                playing ? "Pause" : "Reprendre",
                serviceAction("app.novelia.reader.audio.PLAY_PAUSE", 4104)).build());
            builder.addAction(new Notification.Action.Builder(
                android.R.drawable.ic_media_next, "Suivant",
                serviceAction("app.novelia.reader.audio.NEXT", 4105)).build());
            style.setShowActionsInCompactView(0, 1, 2);
            builder.setStyle(style);
        }
        return builder.build();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}