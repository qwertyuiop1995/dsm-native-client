package io.github.qwertyuiop1995.dsmnativeclient

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import io.github.qwertyuiop1995.dsmnativeclient.ui.LanStashApp
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme

class MainActivity : AppCompatActivity() {
    private val model: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LanStashTheme {
                LanStashApp(model)
            }
        }
    }
}
