const loginForm = document.getElementById('login-form');
const feedbackEl = document.getElementById('login-feedback');

loginForm?.addEventListener('submit', async (event) => {
  event.preventDefault();
  feedbackEl.textContent = 'Validando acesso...';

  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value.trim();

  try {
    const response = await fetch('/api/admin/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });

    const data = await response.json();
    if (!response.ok) {
      feedbackEl.textContent = data.error || 'Falha ao autenticar';
      return;
    }

    window.location.href = '/admin/config';
  } catch (error) {
    feedbackEl.textContent = 'Nao foi possivel acessar o servidor';
  }
});
