#pragma once

// Partial implementation: keep the working Supabase PKCE browser flow selected.
// Enable only after the Android certificate and web audience belong to the same
// accessible Google Cloud project, and the native flow has been validated.
// This is a build-time choice, never an automatic retry after a native error.
#define INGE_GOOGLE_NATIVE_SIGN_IN_CONFIGURED 0
