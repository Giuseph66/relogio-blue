const loginForm = document.getElementById('login-form');
const feedbackEl = document.getElementById('login-feedback');
const submitBtn = document.getElementById('login-submit');

function showError(message) {
  feedbackEl.textContent = message;
  feedbackEl.hidden = !message;
}

loginForm?.addEventListener('submit', async (event) => {
  event.preventDefault();
  showError('');

  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value.trim();
  if (!email || !password) {
    showError('Informe e-mail e senha.');
    return;
  }

  submitBtn.disabled = true;
  submitBtn.textContent = 'Entrando…';

  try {
    const response = await fetch('/api/admin/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    if (!response.ok) {
      showError(response.status === 401 ? 'E-mail ou senha incorretos.' : 'Falha ao autenticar.');
      return;
    }

    window.location.href = '/admin/config';
  } catch (_) {
    showError('Não foi possível conectar ao servidor.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Entrar';
  }
});
