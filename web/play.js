// Start js7800 and load the cartridge (served next to this page).
(function () {
  var ROM = "pinball.a78";
  var status = document.getElementById("status");
  var main = window.js7800 && window.js7800.Main;

  function show(text, isError) {
    status.textContent = text;
    status.className = "status" + (isError ? " status--error" : "");
  }

  if (!main) {
    show("The emulator did not load.", true);
    return;
  }

  main.setErrorHandler(function (error) {
    console.error(error);
    show(String(error), true);
  });
  main.init("js7800__target", { debug: false });

  fetch(ROM)
    .then(function (response) {
      if (!response.ok) throw new Error("Could not load " + ROM + " (" + response.status + ")");
      return response.arrayBuffer();
    })
    .then(function (buffer) {
      var bytes = new Uint8Array(buffer);
      var cart = new Array(bytes.length);
      for (var i = 0; i < bytes.length; i++) cart[i] = bytes[i];
      main.startEmulation(cart);
      show("Press Z to start. Click or press a key for sound.");
    })
    .catch(function (error) {
      show(error.message, true);
    });
})();
