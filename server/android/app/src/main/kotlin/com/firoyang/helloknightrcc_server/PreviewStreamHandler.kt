package com.firoyang.helloknightrcc_server

import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer

class PreviewStreamHandler : EventChannel.StreamHandler {
    private val TAG = "PreviewStreamHandler"
    private var eventSink: EventChannel.EventSink? = null
    private var camera2Manager: Camera2Manager? = null
    
    fun setCamera2Manager(manager: Camera2Manager?) {
        camera2Manager = manager
        // 如果EventChannel已经监听，立即设置回调
        if (eventSink != null && manager != null) {
            manager.previewFrameCallback = { frame ->
                sendFrame(frame)
            }
            Log.d(TAG, "已设置预览帧回调（EventChannel已就绪）")
        }
    }
    
    fun sendFrame(frame: ByteArray) {
        val sink = eventSink
        if (sink != null) {
            try {
                // 确保在主线程发送
                // EventChannel不支持ByteBuffer，需要直接发送ByteArray
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        sink.success(frame)
                    } catch (e: Exception) {
                        Log.e(TAG, "发送预览帧失败", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "发送预览帧异常", e)
            }
        } else {
            Log.w(TAG, "EventSink为null，无法发送预览帧")
        }
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "EventChannel监听已启动")
        eventSink = events
        // 如果Camera2Manager已设置，立即设置回调
        if (camera2Manager != null) {
            camera2Manager?.previewFrameCallback = { frame ->
                sendFrame(frame)
            }
            Log.d(TAG, "已设置预览帧回调（Camera2Manager已就绪）")
        }
    }
    
    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "EventChannel监听已取消")
        eventSink = null
        camera2Manager?.previewFrameCallback = null
    }
}

