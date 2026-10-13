# Migraciones retiradas del flujo (no aplicar)

Estas migraciones nacieron en Android y **nunca se aplicaron** en Supabase DEV
(`aalmeaqhhlhzwwzsbbxz`) ni existen en el contrato Web
(`E1PT04m0/ingeplus-web`, rama `feature/calicatas-cloud-media-04a`).

| Archivo | Qué proponía | Por qué se retira |
|---|---|---|
| `20260930200000_calicata_lab_limits_numeric.sql` | `liquid_limit` / `plastic_limit` numeric y RPC `upsert_my_calicata_lab_result_v03` | Web valida WL/LP como enteros (`validateCalicataLaboratoryForm`) y usa `upsert_my_calicata_lab_result_v02` (integer). |
| `20260930200100_calicata_lab_durable_fields.sql` | D10/D30/D60, NP, observaciones, A-8 visual y `set_my_calicata_stratum_field_classification_v01` / `set_my_calicata_lab_extension_v01` | Campos y RPC paralelos que Web no tiene; la clasificación vigente es la del laboratorio (`primary_sucs`, `is_composite`, `secondary_sucs`, `aashto`). |

Se conservan como registro. Están fuera de `supabase/migrations` para que
`supabase db push` no las aplique. Los valores locales que Android ya hubiera
guardado (D10/D30/D60, NP, observaciones, A-8) se conservan en la ficha local;
no viajan ni influyen en la clasificación.
