package com.ingema.ingeplus;

import android.content.Context;
import android.net.Uri;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;
import com.google.android.gms.tasks.Tasks;
import java.util.concurrent.TimeUnit;
import io.flutter.plugin.common.MethodChannel;

/** Local recognition using the receipt-scanner donor's bundled Latin/Korean model.
 * No cloud OCR and no domain writes. See docs/RENDITIONS_OCR_DONOR_LICENSE.md. */
final class RenditionReceiptOcr {
    static void analyze(Context context, Object argument, MethodChannel.Result result) {
        if (!(argument instanceof String)) {
            result.error("OCR_IMAGE_REQUIRED", "Selecciona una imagen local.", null);
            return;
        }
        new Thread(() -> {
            TextRecognizer recognizer = null;
            try {
                String path = (String) argument;
                Uri uri = Uri.parse(path);
                File file = new File("file".equals(uri.getScheme()) ? uri.getPath() : path);
                File directory = new File(context.getFilesDir(), "renditions/attachments");
                if (!file.getCanonicalPath().startsWith(directory.getCanonicalPath() + File.separator)
                        || !file.isFile() || file.length() == 0 || file.length() > 20971520L)
                    throw new IllegalArgumentException("Imagen local no disponible o fuera de los sustentos.");
                recognizer = TextRecognition.getClient(new KoreanTextRecognizerOptions.Builder().build());
                if (file.getName().toLowerCase(java.util.Locale.ROOT).endsWith(".pdf")) {
                    ArrayList<Map<String, Object>> lines = new ArrayList<>();
                    StringBuilder allText = new StringBuilder();
                    try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
                         PdfRenderer renderer = new PdfRenderer(descriptor)) {
                        // Bound memory per page. All pages are processed sequentially.
                        for (int pageIndex = 0; pageIndex < renderer.getPageCount(); pageIndex++) {
                            try (PdfRenderer.Page page = renderer.openPage(pageIndex)) {
                                float scale = 1800f / Math.max(page.getWidth(), page.getHeight());
                                Bitmap bitmap = Bitmap.createBitmap(Math.max(1, Math.round(page.getWidth() * scale)),
                                        Math.max(1, Math.round(page.getHeight() * scale)), Bitmap.Config.ARGB_8888);
                                try {
                                    bitmap.eraseColor(Color.WHITE);
                                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                                    com.google.mlkit.vision.text.Text text = Tasks.await(
                                            recognizer.process(InputImage.fromBitmap(bitmap, 0)), 30, TimeUnit.SECONDS);
                                    allText.append(text.getText()).append('\n');
                                    for (com.google.mlkit.vision.text.Text.TextBlock block : text.getTextBlocks()) {
                                        for (com.google.mlkit.vision.text.Text.Line line : block.getLines()) {
                                            Map<String, Object> row = new HashMap<>();
                                            row.put("text", line.getText());
                                            float confidence = line.getConfidence();
                                            row.put("confidence", Float.isNaN(confidence) ? null : (double) confidence);
                                            lines.add(row);
                                        }
                                    }
                                } finally { bitmap.recycle(); }
                            }
                        }
                    }
                    Map<String, Object> payload = new HashMap<>();
                    payload.put("text", allText.toString()); payload.put("lines", lines);
                    recognizer.close();
                    new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> result.success(payload));
                    return;
                }
                InputImage image = InputImage.fromFilePath(context, Uri.fromFile(file));
                final TextRecognizer client = recognizer;
                recognizer.process(image).addOnSuccessListener(text -> {
                    ArrayList<Map<String, Object>> lines = new ArrayList<>();
                    for (com.google.mlkit.vision.text.Text.TextBlock block : text.getTextBlocks()) {
                        for (com.google.mlkit.vision.text.Text.Line line : block.getLines()) {
                            Map<String, Object> row = new HashMap<>();
                            row.put("text", line.getText());
                            float confidence = line.getConfidence();
                            row.put("confidence", Float.isNaN(confidence) ? null : (double) confidence);
                            lines.add(row);
                        }
                    }
                    Map<String, Object> payload = new HashMap<>();
                    payload.put("text", text.getText());
                    payload.put("lines", lines);
                    result.success(payload);
                }).addOnFailureListener(error -> result.error("OCR_FAILED",
                        "No se pudo reconocer la imagen. Intenta con una foto más nítida.", null))
                  .addOnCompleteListener(task -> client.close());
            } catch (Exception error) {
                if (recognizer != null) recognizer.close();
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                        result.error("OCR_IMAGE_INVALID", "No se pudo leer la imagen local del sustento.", null));
            }
        }, "rendition-local-ocr").start();
    }
}
