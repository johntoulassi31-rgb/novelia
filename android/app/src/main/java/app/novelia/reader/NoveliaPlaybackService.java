package app.novelia.reader;

import android.app.Service;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.media.session.MediaSession;
import android.app.PendingIntent;
import android.content.Context;

public class NoveliaPlaybackService extends Service {
    public static final String ACTION_START = "app.novelia.reader.audio.START";
    public static final String ACTION_STOP = "app.novelia.reader.audio.STOP";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_TOKEN = "session_token";
    private static final String CHANNEL_ID = "novelia_audio";
    private static final int NOTIFICATION_ID = 4102;

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
        MediaSession.Token token = intent.getParcelableExtra(EXTRA_TOKEN);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID) : new Notification.Builder(this);
        builder.setContentTitle(title == null ? "Novelia" : title)
            .setContentText("Lecture audio en cours")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC);
        if (token != null && Build.VERSION.SDK_INT >= 21) {
            builder.setStyle(new Notification.MediaStyle().setMediaSession(token)
                .setShowActionsInCompactView(0));
        }
        startForeground(NOTIFICATION_ID, builder.build());
        return START_NOT_STICKY;
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
