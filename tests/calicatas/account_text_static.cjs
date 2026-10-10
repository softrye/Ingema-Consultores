// Política de texto de cuentas (AccountText.js), extraída de InGeCoreFlow.qml.
// AGENTS regla 8: el correo se conserva exactamente; regla 9: la capitalización
// solo se aplica a nombres. Verificada contra el original el 2026-10-10.
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const strip = (s) => s.split(/\r?\n/).filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const lib = vm.createContext({ Math, Number, String });
vm.runInContext(strip(fs.readFileSync(path.join(root, "qml/Mobile/lib/AccountText.js"), "utf8")), lib);
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };
check("correo exacto: sin recortes, sin capitalización, sin minúsculas", () => {
    for (const email of ["Ana.Perez@Ingema.PE", "  geo@x.com ", "UPPER@MAIL.COM"])
        assert.strictEqual(lib.displayEmailExact(email, ""), email);
    assert.strictEqual(lib.displayPersonName("Ana.Perez@Ingema.PE", ""), "Ana.Perez@Ingema.PE");
    assert.strictEqual(lib.displayText("MiXeD@Mail.com", "nombre", ""), "MiXeD@Mail.com");
    assert.strictEqual(lib.emailLookupKey("  Ana@X.COM "), "ana@x.com");
});
check("nombres: capitalización por palabra, guiones/apóstrofes, mayúsculas internas", () => {
    assert.strictEqual(lib.displayPersonName("  maría   JOSÉ o'neil-garcía ", ""), "María José O'Neil-García");
    assert.strictEqual(lib.displayPersonName("mcDonald", ""), "McDonald");
    assert.strictEqual(lib.displayPersonName("juan pérez", "", false), "juan pérez");
    assert.strictEqual(lib.personInitials("ana maría lópez", 3), "AML");
    assert.strictEqual(lib.personInitials("x@y.com", 2), "");
});
check("respaldo cuando el valor está vacío", () => {
    assert.strictEqual(lib.displayEmailExact("   ", "fallback@x.com"), "fallback@x.com");
    assert.strictEqual(lib.displayPersonName("", "pedro"), "Pedro");
    assert.strictEqual(lib.originalText(null, 5), "5");
});
console.log("ACCOUNT_TEXT_STATIC PASS " + passed + " checks");
