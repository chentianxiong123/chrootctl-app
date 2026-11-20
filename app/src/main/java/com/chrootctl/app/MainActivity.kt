package com.chrootctl.app

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import java.io.File
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {

    private lateinit var etRootfs: EditText
    private lateinit var etPort: EditText
    private lateinit var tvOutput: TextView
    private lateinit var scroll: ScrollView

    private val PREF = "chrootctl"
    private val KEY_ROOTFS = "rootfs"
    private val KEY_PORT = "port"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        etRootfs = findViewById(R.id.etRootfs)
        etPort = findViewById(R.id.etPort)
        tvOutput = findViewById(R.id.tvOutput)
        scroll = findViewById(R.id.root)

        val sp = getSharedPreferences(PREF, MODE_PRIVATE)
        etRootfs.setText(sp.getString(KEY_ROOTFS,
            "/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs"))
        etPort.setText(sp.getInt(KEY_PORT, 8022).toString())

        findViewById<Button>(R.id.btnStart).setOnClickListener { run("start") }
        findViewById<Button>(R.id.btnStop).setOnClickListener { run("stop") }
        findViewById<Button>(R.id.btnStatus).setOnClickListener { run("status") }
        findViewById<Button>(R.id.btnSsh).setOnClickListener { runSshTest() }
        findViewById<Button>(R.id.btnClear).setOnClickListener {
            tvOutput.text = ""
            try {
                File(getExternalFilesDir(null), "chrootctl.log").writeText("")
            } catch (_: Exception) {}
            Toast.makeText(this, "日志已清空", Toast.LENGTH_SHORT).show()
        }

        loadLogToView()
        append("ChrootCtl 就绪")
        thread { runRoot("id -u") { append("su 测试: uid=$it") } }
    }

    private fun run(action: String) {
        val rootfs = etRootfs.text.toString().trim()
        val port = etPort.text.toString().trim().ifEmpty { "8022" }
        getSharedPreferences(PREF, MODE_PRIVATE).edit()
            .putString(KEY_ROOTFS, rootfs).putInt(KEY_PORT, port.toInt()).apply()

        append(">>> $action (rootfs=$rootfs port=$port)")
        thread {
            val script = loadScript().replace("__ROOTFS__", rootfs)
                .replace("__PORT__", port).replace("__ACTION__", action)
            runRoot(script) { append(it) }
        }
    }

    private fun runSshTest() {
        val port = etPort.text.toString().trim().ifEmpty { "8022" }
        append(">>> ssh 端口测试 $port")
        thread { runRoot("ss -tln | grep ':$port ' && echo 监听中 || echo 无监听") { append(it) } }
    }

    // 从 assets 读脚本
    private fun loadScript(): String =
        assets.open("chroot.sh").bufferedReader().use { it.readText() }

    private fun runRoot(cmd: String, cb: (String) -> Unit) {
        try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            p.waitFor()
            if (out.isNotBlank()) cb(out.trim())
            if (err.isNotBlank()) cb("[err] " + err.trim())
        } catch (e: Exception) {
            cb("[异常] ${e.message}")
        }
    }

    // 启动时加载持久化日志到输出框(重启不丢)
    private fun loadLogToView() {
        try {
            val f = File(getExternalFilesDir(null), "chrootctl.log")
            if (f.exists()) {
                val content = f.readText().trim()
                if (content.isNotBlank()) {
                    tvOutput.text = content
                    scroll.post { scroll.fullScroll(android.view.View.FOCUS_DOWN) }
                }
            }
        } catch (_: Exception) {}
    }

    private fun append(s: String) {
        runOnUiThread {
            tvOutput.append("\n$s")
            scroll.post { scroll.fullScroll(android.view.View.FOCUS_DOWN) }
        }
        // 同时落盘(外部存储 app 私有目录, root 可读)
        try {
            File(getExternalFilesDir(null), "chrootctl.log").appendText("$s\n")
        } catch (_: Exception) {}
    }
}