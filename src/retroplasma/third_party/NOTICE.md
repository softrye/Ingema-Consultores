# RockTree / CRN

El usuario proporcionó `earth-reverse-engineering-master.zip` para integrar sus funciones. Procedencia indicada en sus fuentes: https://github.com/retroplasma/earth-reverse-engineering.

- `rocktree.proto`: esquema aportado, sin cambios de campos ni tipos. La implementación Qt de lectura de wire format está en `RetroplasmaRocktree.cpp`.
- Los algoritmos de vértices delta, UV, índices, capas y OBB se adaptan de `client/rocktree_decoder.h` y `client/rocktree_ex.h` del archivo aportado, añadiendo comprobaciones de límites.
- `crn/crn_decomp.h` y `crn/crnlib.h`: Rich Geldreich / Tenacious Software LLC, licencia ZLIB incluida al final de ambos archivos. Cambios locales: `ptr_bits` usa `std::uintptr_t` para Android arm64/Win64; se completa la directiva `#ifndef NOMINMAX` incompleta del bloque de desarrollo; se normalizan espacios finales. El wrapper proporciona la adaptación del asignador de MSVC y valida rangos antes de llamar al descompresor.

El código no incluye SDL, otro bucle de animaciones ni un visor Cesium paralelo. Los datos e imágenes remotos no forman parte de estos archivos. El transporte emplea HTTPS y no requiere una API key; su disponibilidad depende de una interfaz no documentada.
