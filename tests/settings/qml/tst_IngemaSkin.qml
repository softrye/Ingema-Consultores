import QtQuick
import QtTest
import "../../../qml/Mobile/renditions" as Renditions

TestCase {
    id: test
    name: "IngemaSkin"
    when: windowShown
    width: 412; height: 915; visible: true
    Component { id: backdropComponent; Renditions.RendicionesSyncBackdrop { width: 412; height: 915; running: false; reducedMotion: true } }
    function test_skin_data() {
        return [
            {tag:"default-light",skin:"none",dark:false,corporate:false,galaxy:false},
            {tag:"default-dark",skin:"none",dark:true,corporate:false,galaxy:false},
            {tag:"ingema-light",skin:"ingema",dark:false,corporate:true,galaxy:false},
            {tag:"ingema-dark",skin:"ingema",dark:true,corporate:true,galaxy:false},
            {tag:"galaxy",skin:"galaxias",dark:true,corporate:false,galaxy:true}
        ]
    }
    function test_skin(data) {
        var backdrop=createTemporaryObject(backdropComponent,test,{skin:data.skin,dark:data.dark})
        verify(backdrop!==null)
        compare(backdrop.corporate,data.corporate)
        compare(backdrop.galaxy,data.galaxy)
        var base=findChild(backdrop,"ingemaBackground")
        verify(base!==null)
        compare(base.visible,data.corporate)
        var aurora=findChild(backdrop,"backdropAurora")
        verify(aurora!==null)
        compare(aurora.visible,data.corporate || data.dark && !data.galaxy)
        compare(aurora.running,false)
        if(data.corporate) {
            compare(aurora.primaryColor,"#0654a2")
            compare(aurora.accentColor,"#486426")
        }
    }
}
