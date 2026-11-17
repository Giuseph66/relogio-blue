(() => {
  const form = document.getElementById('push-form');
  const status = document.getElementById('push-status');
  const submit = form.querySelector('button[type="submit"]');
  async function api(action, options = {}) {
    const response = await fetch(`/api/admin/push/${action}`, {
      credentials: 'same-origin', cache: 'no-store', ...options,
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Falha ao acessar o servidor.');
    return data;
  }
  api('status').then(data => {
    status.textContent = data.enabled
      ? `${data.subscriptions} celular(es)/navegador(es) inscrito(s). O aviso será enviado a todos.`
      : 'Web Push desativado. Configure as chaves VAPID no servidor e reinicie o serviço.';
    submit.disabled = !data.enabled;
  }).catch(error => { status.textContent = error.message; submit.disabled = true; });
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (!form.reportValidity()) return;
    submit.disabled = true;
    status.textContent = 'Enviando avisos...';
    try {
      const data = await api('send', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: form.elements.title.value, body: form.elements.body.value }),
      });
      status.textContent = `${data.accepted} aceito(s) pelo serviço de push; ${data.expired} inscrição(ões) expirada(s); ${data.failed} falha(s). Aceitação não confirma leitura ou entrega no aparelho.`;
    } catch (error) { status.textContent = error.message; }
    finally { submit.disabled = false; }
  });
})();
