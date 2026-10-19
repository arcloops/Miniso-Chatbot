const lines = [
  ["in", "WhatsApp", "Do you have the white lamp in stock?"],
  ["out", "acxio", "Yes. Two are left at Banani. I can hold one for you."],
  ["in", "Messenger", "Can someone call me after 6?"],
  ["out", "acxio", "Booked. Naima will call you at 6:15."],
  ["in", "Instagram", "Is the showroom open on Friday?"],
  ["out", "acxio", "Open 11 to 8. I can reserve a viewing."]
];

function bootThread() {
  const box = document.querySelector("[data-thread]");
  if (!box) return;
  let i = 0;
  const paint = () => {
    const [kind, who, text] = lines[i % lines.length];
    const node = document.createElement("div");
    node.className = `bubble ${kind === "out" ? "out" : ""}`;
    node.innerHTML = `${text}<small>${who}</small>`;
    box.appendChild(node);
    while (box.children.length > 4) box.removeChild(box.firstChild);
    i += 1;
  };
  paint();
  setInterval(paint, 2200);
}

function bootStage() {
  document.querySelectorAll(".hero, .page-hero").forEach((hero) => {
  const pieces = [...hero.querySelectorAll("[data-depth]")];
  if (!pieces.length) return;
  hero.addEventListener("pointermove", (event) => {
    const rect = hero.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    pieces.forEach((piece) => {
      const depth = Number(piece.dataset.depth);
      piece.style.transform = `translate3d(${x * depth}px, ${y * depth}px, 0)`;
    });
  });
  });
}

function bootReveal() {
  const nodes = document.querySelectorAll(".watched");
  if (!nodes.length) return;
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) entry.target.classList.add("show");
    });
  }, { threshold: 0.18 });
  nodes.forEach((node) => observer.observe(node));
}

function bootCounts() {
  document.querySelectorAll("[data-count]").forEach((node) => {
    const target = Number(node.dataset.count);
    const observer = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting) return;
      observer.disconnect();
      const start = performance.now();
      const tick = (now) => {
        const progress = Math.min(1, (now - start) / 900);
        node.textContent = Math.round(target * progress).toString();
        if (progress < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }, { threshold: 0.6 });
    observer.observe(node);
  });
}

const frames = [
  ["assets/desk-queue.jpg", "Queue", "Every connected channel, in one list.", "Conversations from more than one channel listed together on the acxio desk."],
  ["assets/desk-thread.jpg", "Thread", "The history stays beside the reply.", "An open conversation on the acxio desk, ready to answer."],
  ["assets/inbox.png", "Inboxes", "Each channel is named on the side.", "Named WhatsApp and Messenger inboxes in the acxio sidebar."]
];

function bootShow() {
  document.querySelectorAll("[data-show]").forEach((root) => {
    const img = root.querySelector("[data-show-img]");
    const label = root.querySelector("[data-show-label]");
    const copy = root.querySelector("[data-show-copy]");
    const buttons = [...root.querySelectorAll("[data-show-go]")];
    let index = 0;
    let timer;

    const paint = (next) => {
      index = next;
      const [src, name, text, alt] = frames[index];
      img.src = src;
      img.alt = alt;
      label.textContent = name;
      copy.textContent = text;
      buttons.forEach((button, i) => button.classList.toggle("on", i === index));
    };

    const arm = () => {
      clearInterval(timer);
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      timer = setInterval(() => paint((index + 1) % frames.length), 4200);
    };

    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        paint(Number(button.dataset.showGo));
        arm();
      });
    });
    arm();
  });
}

function bootMenu() {
  const nav = document.querySelector(".nav");
  const button = document.querySelector(".menu-btn");
  if (!nav || !button) return;
  button.addEventListener("click", () => {
    const open = nav.classList.toggle("open");
    button.setAttribute("aria-expanded", open ? "true" : "false");
  });
}

function bootForm() {
  const form = document.querySelector("[data-form]");
  if (!form) return;
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const note = form.querySelector(".note");
    note.textContent = "Received. A person from acxio will write back.";
    form.reset();
  });
}

bootThread();
bootStage();
bootReveal();
bootCounts();
bootShow();
bootMenu();
bootForm();
