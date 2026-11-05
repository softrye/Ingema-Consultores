#pragma once

// Android certificates (debug/release) and the configured web audience belong
// to ingeplus-drive. Supabase Dev validates that audience and the nonce.
// Native errors stay explicit; never retry through the browser on Android.
// Device/build verification is performed by the user after compiling.
#define INGE_GOOGLE_NATIVE_SIGN_IN_CONFIGURED 1
