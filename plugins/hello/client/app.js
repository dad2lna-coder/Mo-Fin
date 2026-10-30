async function callHost(method, params) {
  if (!window.MoFinHost || !window.MoFinHost.call) {
    alert("MoFinHost bridge is not available. Ensure plugin is running inside MoFin.");
    return null;
  }
  return await window.MoFinHost.call(method, params);
}

async function fetchUserContext() {
  try {
    const context = await callHost("getUserContext", {});
    document.getElementById("userContextOutput").innerText = JSON.stringify(context, null, 2);
  } catch (err) {
    document.getElementById("userContextOutput").innerText = "Error: " + err.message;
  }
}

async function registerHomeRow() {
  try {
    await callHost("registerHomeRow", {
      id: "hello_sample_row",
      title: "Hello World Picks",
      items: [
        {
          id: "sample_stream_1",
          title: "Big Buck Bunny Stream",
          subtitle: "Sample HLS Test Stream",
          imageUrl: "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg",
          streamUrl: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
        }
      ]
    });
    alert("Registered 'Hello World Picks' row! Return to Home screen to see it.");
  } catch (err) {
    alert("Failed to register home row: " + err.message);
  }
}

async function saveStorage() {
  try {
    await callHost("storageSet", { key: "greeting", value: "Hello MoFin!" });
    document.getElementById("storageOutput").innerText = "Saved 'greeting' = 'Hello MoFin!'";
  } catch (err) {
    document.getElementById("storageOutput").innerText = "Error: " + err.message;
  }
}

async function readStorage() {
  try {
    const val = await callHost("storageGet", { key: "greeting" });
    document.getElementById("storageOutput").innerText = "Read 'greeting' = " + JSON.stringify(val);
  } catch (err) {
    document.getElementById("storageOutput").innerText = "Error: " + err.message;
  }
}

window.addEventListener("DOMContentLoaded", () => {
  setTimeout(() => {
    registerHomeRow();
  }, 500);
});
