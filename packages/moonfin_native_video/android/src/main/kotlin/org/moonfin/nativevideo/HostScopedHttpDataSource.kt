package org.moonfin.nativevideo

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Sends Authorization only when the request host is the configured source.
 * [DefaultHttpDataSource] keeps that header on every redirect hop, which would
 * hand a Dispatcharr token to stitcher.pluto.tv. Redirects are followed here
 * instead, and the header is decided again for each host. [getUri] is the
 * final URL so HLS can resolve a relative WebVTT rendition against it.
 */
@UnstableApi
internal class PlaybackHttpDataSourceFactory : DataSource.Factory {
    private val plain = DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
        .setReadTimeoutMs(READ_TIMEOUT_MS)
    private val scoped = HostScopedHttpDataSource.Factory()

    @Volatile var credentialHost: String? = null
    @Volatile var authorization: String? = null

    fun setDefaultRequestProperties(headers: Map<String, String>) {
        plain.setDefaultRequestProperties(headers)
        scoped.setDefaultRequestProperties(headers)
        scoped.allowedHost = credentialHost
        scoped.authorization = authorization
    }

    override fun createDataSource(): DataSource {
        scoped.allowedHost = credentialHost
        scoped.authorization = authorization
        return if (credentialHost.isNullOrBlank()) {
            plain.createDataSource()
        } else {
            scoped.createDataSource()
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 120_000
        const val READ_TIMEOUT_MS = 120_000
    }
}

@UnstableApi
internal class HostScopedHttpDataSource private constructor(
    private val defaultRequestProperties: HttpDataSource.RequestProperties,
    private val allowedHost: () -> String?,
    private val authorization: () -> String?,
) : BaseDataSource(true), HttpDataSource {
    class Factory : HttpDataSource.BaseFactory() {
        @Volatile var allowedHost: String? = null
        @Volatile var authorization: String? = null

        override fun createDataSourceInternal(
            defaultRequestProperties: HttpDataSource.RequestProperties,
        ): HttpDataSource {
            return HostScopedHttpDataSource(
                defaultRequestProperties,
                { allowedHost },
                { authorization },
            )
        }
    }

    private val requestProperties = LinkedHashMap<String, String>()
    private var connection: HttpURLConnection? = null
    private var inputStream: InputStream? = null
    private var openedUri: Uri? = null
    private var responseCode: Int = -1
    private var responseHeaders: Map<String, List<String>> = emptyMap()
    private var bytesRemaining: Long = 0
    private var opened = false

    override fun setRequestProperty(name: String, value: String) {
        requestProperties[name] = value
    }

    override fun clearRequestProperty(name: String) {
        requestProperties.remove(name)
    }

    override fun clearAllRequestProperties() {
        requestProperties.clear()
    }

    override fun getResponseCode(): Int = responseCode

    override fun getResponseHeaders(): Map<String, List<String>> = responseHeaders

    override fun getUri(): Uri? = openedUri

    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        try {
            var url = URL(dataSpec.uri.toString())
            var method = httpMethod(dataSpec.httpMethod)
            var body = dataSpec.httpBody
            var redirects = 0
            while (redirects++ <= MAX_REDIRECTS) {
                val next = openConnection(url, method, body, dataSpec)
                val code = next.responseCode
                if (isRedirect(code)) {
                    val location = next.getHeaderField("Location")
                    next.disconnect()
                    if (location.isNullOrBlank()) {
                        throw invalidCode(code, next, dataSpec, ByteArray(0))
                    }
                    val resolved = URL(url, location)
                    if (resolved.protocol != "http" && resolved.protocol != "https") {
                        throw HttpDataSource.HttpDataSourceException(
                            "Unsupported redirect to ${resolved.protocol}",
                            dataSpec,
                            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                            HttpDataSource.HttpDataSourceException.TYPE_OPEN,
                        )
                    }
                    url = resolved
                    if (code != 307 && code != 308) {
                        method = "GET"
                        body = null
                    }
                    continue
                }
                connection = next
                responseCode = code
                val headers = HashMap<String, List<String>>()
                for ((key, value) in next.headerFields) {
                    if (key != null) headers[key] = value
                }
                responseHeaders = headers
                openedUri = Uri.parse(url.toString())
                if (code !in 200..299) {
                    val errorBody = readErrorBody(next)
                    throw invalidCode(code, next, dataSpec, errorBody)
                }
                if (dataSpec.position > 0 && code != 206) {
                    throw invalidCode(code, next, dataSpec, ByteArray(0))
                }
                inputStream = next.inputStream
                val contentLength = next.getHeaderField("Content-Length")?.toLongOrNull()
                    ?: C.LENGTH_UNSET.toLong()
                bytesRemaining = when {
                    dataSpec.length != C.LENGTH_UNSET.toLong() -> dataSpec.length
                    contentLength >= 0 -> contentLength
                    else -> C.LENGTH_UNSET.toLong()
                }
                opened = true
                transferStarted(dataSpec)
                return bytesRemaining
            }
            throw HttpDataSource.HttpDataSourceException(
                "Too many redirects",
                dataSpec,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                HttpDataSource.HttpDataSourceException.TYPE_OPEN,
            )
        } catch (error: HttpDataSource.HttpDataSourceException) {
            closeConnectionQuietly()
            throw error
        } catch (error: IOException) {
            closeConnectionQuietly()
            throw HttpDataSource.HttpDataSourceException(
                error,
                dataSpec,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                HttpDataSource.HttpDataSourceException.TYPE_OPEN,
            )
        }
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (bytesRemaining == 0L) return C.RESULT_END_OF_INPUT
        val stream = inputStream ?: throw HttpDataSource.HttpDataSourceException(
            DataSpec(openedUri ?: Uri.parse("about:blank")),
            PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            HttpDataSource.HttpDataSourceException.TYPE_READ,
        )
        return try {
            val wanted = if (bytesRemaining == C.LENGTH_UNSET.toLong()) {
                length
            } else {
                minOf(length.toLong(), bytesRemaining).toInt()
            }
            val read = stream.read(buffer, offset, wanted)
            if (read == -1) {
                C.RESULT_END_OF_INPUT
            } else {
                if (bytesRemaining != C.LENGTH_UNSET.toLong()) {
                    bytesRemaining -= read.toLong()
                }
                bytesTransferred(read)
                read
            }
        } catch (error: IOException) {
            throw HttpDataSource.HttpDataSourceException(
                error,
                DataSpec(openedUri ?: Uri.parse("about:blank")),
                PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
                HttpDataSource.HttpDataSourceException.TYPE_READ,
            )
        }
    }

    override fun close() {
        try {
            inputStream?.close()
        } catch (_: IOException) {
        } finally {
            inputStream = null
            closeConnectionQuietly()
            if (opened) {
                opened = false
                transferEnded()
            }
        }
    }

    private fun openConnection(
        url: URL,
        method: String,
        body: ByteArray?,
        dataSpec: DataSpec,
    ): HttpURLConnection {
        val connection = url.openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.connectTimeout = CONNECT_TIMEOUT_MS
        connection.readTimeout = READ_TIMEOUT_MS
        connection.requestMethod = method
        val headers = LinkedHashMap<String, String>()
        headers.putAll(defaultRequestProperties.snapshot)
        headers.putAll(dataSpec.httpRequestHeaders)
        headers.putAll(requestProperties)
        if (allows(url.host)) {
            authorization()?.takeIf { it.isNotBlank() }?.let { headers["Authorization"] = it }
        } else {
            headers.keys.filter { it.equals("Authorization", ignoreCase = true) }
                .toList()
                .forEach { headers.remove(it) }
        }
        for ((name, value) in headers) {
            connection.setRequestProperty(name, value)
        }
        val range = rangeHeader(dataSpec)
        if (range != null) connection.setRequestProperty("Range", range)
        if (body != null && method != "GET" && method != "HEAD") {
            connection.doOutput = true
            connection.outputStream.use { it.write(body) }
        }
        connection.connect()
        return connection
    }

    private fun allows(host: String?): Boolean = hostMatchesCredential(host, allowedHost())

    private fun closeConnectionQuietly() {
        try {
            connection?.disconnect()
        } catch (_: Exception) {
        } finally {
            connection = null
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 120_000
        const val READ_TIMEOUT_MS = 120_000
        const val MAX_REDIRECTS = 20

        fun httpMethod(method: Int): String = when (method) {
            DataSpec.HTTP_METHOD_POST -> "POST"
            DataSpec.HTTP_METHOD_HEAD -> "HEAD"
            else -> "GET"
        }

        fun isRedirect(code: Int): Boolean =
            code == 300 || code == 301 || code == 302 || code == 303 || code == 307 || code == 308

        fun rangeHeader(dataSpec: DataSpec): String? {
            if (dataSpec.position == 0L && dataSpec.length == C.LENGTH_UNSET.toLong()) {
                return null
            }
            val end = if (dataSpec.length == C.LENGTH_UNSET.toLong()) {
                ""
            } else {
                (dataSpec.position + dataSpec.length - 1).toString()
            }
            return "bytes=${dataSpec.position}-$end"
        }

        fun readErrorBody(connection: HttpURLConnection): ByteArray {
            val stream = connection.errorStream ?: return ByteArray(0)
            return try {
                val buffer = ByteArray(1024)
                val read = stream.read(buffer)
                if (read <= 0) ByteArray(0) else buffer.copyOf(read)
            } catch (_: IOException) {
                ByteArray(0)
            }
        }

        fun invalidCode(
            code: Int,
            connection: HttpURLConnection,
            dataSpec: DataSpec,
            body: ByteArray,
        ): HttpDataSource.InvalidResponseCodeException {
            val headers = HashMap<String, List<String>>()
            for ((key, value) in connection.headerFields) {
                if (key != null) headers[key] = value
            }
            return HttpDataSource.InvalidResponseCodeException(
                code,
                connection.responseMessage,
                null,
                headers,
                dataSpec,
                body,
            )
        }
    }
}

internal fun hostMatchesCredential(host: String?, allowed: String?): Boolean {
    if (host.isNullOrBlank() || allowed.isNullOrBlank()) return false
    val left = host.lowercase()
    val right = allowed.lowercase()
    return left == right || left.endsWith(".$right")
}
