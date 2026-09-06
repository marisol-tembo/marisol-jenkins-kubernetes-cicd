(() => {
  const path = document.getElementById("path");
  if (!path) return;

  const hops = path.querySelectorAll("span");
  let i = 0;
  setInterval(() => {
    hops.forEach((el, idx) => {
      el.style.transform = idx === i ? "translateY(-3px)" : "translateY(0)";
      el.style.background =
        idx === i
          ? "color-mix(in srgb, #ff7a9a 22%, white)"
          : "color-mix(in srgb, white 75%, transparent)";
    });
    i = (i + 1) % hops.length;
  }, 900);
})();
