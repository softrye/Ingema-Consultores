/* SPDX-License-Identifier: GPL-3.0-only
 * Nothing Files ACTION_VIEW/ACTION_SEND adaptation. No navigation or Back callback.
 */
package com.ingema.ingeplus;

import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import java.util.List;
import android.net.Uri;
import android.webkit.MimeTypeMap;
import androidx.core.content.FileProvider;
import java.io.File;
import java.util.Locale;

public final class NothingFileBridge {
    private NothingFileBridge() {}
    public static byte[] thumbnail(String path) {
        android.media.MediaMetadataRetriever reader=new android.media.MediaMetadataRetriever();
        android.graphics.Bitmap bitmap=null;
        try {
            reader.setDataSource(path);
            bitmap=reader.getScaledFrameAtTime(0,android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,160,160);
            if(bitmap==null) return null;
            java.io.ByteArrayOutputStream output=new java.io.ByteArrayOutputStream();
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,output);
            return output.toByteArray();
        } catch(Exception error) { return null; }
        finally { if(bitmap!=null) bitmap.recycle(); try { reader.release(); } catch(Exception ignored) {} }
    }
    public static boolean hasAccess() {
        return android.os.Build.VERSION.SDK_INT < 30 || android.os.Environment.isExternalStorageManager();
    }
    public static void requestAccess(Context context) {
        Intent intent = new Intent(android.os.Build.VERSION.SDK_INT >= 30
            ? android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
            : android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:" + context.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(intent);
    }
    // Copia exacta (mismos bytes) de un archivo propio a la galería del sistema:
    // MediaStore Pictures/InGePlus en Android 10+ (sin permisos), y
    // Pictures/InGePlus + escaneo de medios en Android 9. No decodifica ni
    // recomprime: el archivo guardado es el que la app ya publicó.
    public static String saveToPictures(Context context, String path, String displayName, String mime) {
        File source = new File(path);
        if (!source.isFile()) return "El archivo no está disponible.";
        try {
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                android.content.ContentResolver resolver = context.getContentResolver();
                android.content.ContentValues values = new android.content.ContentValues();
                values.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, displayName);
                values.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime);
                values.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH,
                        android.os.Environment.DIRECTORY_PICTURES + "/InGePlus");
                values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1);
                Uri target = resolver.insert(android.provider.MediaStore.Images.Media.getContentUri(
                        android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY), values);
                if (target == null) return "Android no pudo crear la imagen en la galería.";
                try (java.io.InputStream in = new java.io.FileInputStream(source);
                     java.io.OutputStream out = resolver.openOutputStream(target)) {
                    if (out == null) throw new java.io.IOException("Sin destino en la galería");
                    copy(in, out);
                } catch (Exception error) {
                    // Solo se retira la entrada pendiente que esta misma llamada creó.
                    resolver.delete(target, null, null);
                    throw error;
                }
                values.clear();
                values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0);
                resolver.update(target, values, null, null);
                return "";
            }
            if (context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    != PackageManager.PERMISSION_GRANTED)
                return "Concede el permiso de almacenamiento para guardar la imagen en la galería.";
            File folder = new File(android.os.Environment.getExternalStoragePublicDirectory(
                    android.os.Environment.DIRECTORY_PICTURES), "InGePlus");
            if (!folder.isDirectory() && !folder.mkdirs()) return "No se pudo crear la carpeta Pictures/InGePlus.";
            File target = new File(folder, displayName);
            int dot = displayName.lastIndexOf('.');
            String stem = dot < 0 ? displayName : displayName.substring(0, dot);
            String ext = dot < 0 ? "" : displayName.substring(dot);
            for (int n = 1; target.exists(); ++n) target = new File(folder, stem + " (" + n + ")" + ext);
            try (java.io.InputStream in = new java.io.FileInputStream(source);
                 java.io.OutputStream out = new java.io.FileOutputStream(target)) {
                copy(in, out);
            }
            android.media.MediaScannerConnection.scanFile(context,
                    new String[] { target.getAbsolutePath() }, new String[] { mime }, null);
            return "";
        } catch (Exception error) {
            return "Android no pudo guardar la imagen (" + error.getClass().getSimpleName() + ").";
        }
    }
    private static void copy(java.io.InputStream in, java.io.OutputStream out) throws java.io.IOException {
        byte[] buffer = new byte[64 * 1024];
        for (int read; (read = in.read(buffer)) > 0; ) out.write(buffer, 0, read);
        out.flush();
    }
    public static String open(Context context, String path, boolean chooser, boolean share) {
        try {
            File file = new File(path);
            if (!file.isFile()) return "El archivo no está disponible.";
            Uri uri = FileProvider.getUriForFile(context, context.getPackageName() + ".nothingfiles", file);
            String name = file.getName();
            int dot = name.lastIndexOf('.');
            String ext = dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
            String mime = "xlsx".equals(ext) ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    : "pdf".equals(ext) ? "application/pdf"
                    : MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
            if (mime == null) mime = "application/octet-stream";
            Intent target = new Intent(share ? Intent.ACTION_SEND : Intent.ACTION_VIEW);
            if (share) { target.setType(mime); target.putExtra(Intent.EXTRA_STREAM, uri); }
            else target.setDataAndType(uri, mime);
            target.setClipData(ClipData.newRawUri(name, uri));
            target.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            // Provider stays exported=false: every compatible receiver gets an
            // explicit, temporary read grant before anything is launched.
            List<ResolveInfo> receivers = context.getPackageManager()
                    .queryIntentActivities(target, PackageManager.MATCH_DEFAULT_ONLY);
            if (receivers == null || receivers.isEmpty()) return "No hay una aplicación compatible instalada.";
            for (ResolveInfo receiver : receivers) {
                if (receiver.activityInfo == null) continue;
                context.grantUriPermission(receiver.activityInfo.packageName, uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
            Intent launch = target;
            if (chooser || share) {
                launch = Intent.createChooser(target, share ? "Compartir archivo" : "Abrir con");
                // The chooser itself must carry the grant and the ClipData too.
                launch.setClipData(ClipData.newRawUri(name, uri));
                launch.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(launch);
            return "";
        } catch (android.content.ActivityNotFoundException error) {
            return "No hay una aplicación compatible instalada.";
        } catch (Exception error) {
            return "Android no pudo abrir o compartir este archivo (" + error.getClass().getSimpleName() + ").";
        }
    }
}
