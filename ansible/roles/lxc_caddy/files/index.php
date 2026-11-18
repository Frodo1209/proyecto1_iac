<?php
// Tablón de notas: aplicación sencilla para probar Caddy + PHP-FPM + PostgreSQL
// en contenedores LXC

$config = require '/etc/notas/config.php';
$db = $config['db'];
$error = null;
$notas = [];
$version = null;

try {
    $pdo = new PDO(
        "pgsql:host={$db['host']};dbname={$db['name']}",
        $db['user'],
        $db['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $accion = $_POST['accion'] ?? '';
        if ($accion === 'crear') {
            $autor = trim($_POST['autor'] ?? '');
            $texto = trim($_POST['texto'] ?? '');
            if ($autor !== '' && $texto !== '') {
                $st = $pdo->prepare('INSERT INTO notas (autor, texto) VALUES (?, ?)');
                $st->execute([mb_substr($autor, 0, 50), mb_substr($texto, 0, 500)]);
            }
        } elseif ($accion === 'borrar') {
            $st = $pdo->prepare('DELETE FROM notas WHERE id = ?');
            $st->execute([(int) ($_POST['id'] ?? 0)]);
        }
        // Post/Redirect/Get: al recargar no se reenvía el formulario
        header('Location: /');
        exit;
    }

    $notas = $pdo->query('SELECT id, autor, texto, creada FROM notas ORDER BY creada DESC')->fetchAll();
    $version = $pdo->query('SHOW server_version')->fetchColumn();
} catch (PDOException $e) {
    $error = $e->getMessage();
}

function e(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tablón de notas</title>
    <link rel="stylesheet" href="/style.css">
</head>
<body>
<main>
    <h1>Tablón de notas</h1>

    <section class="estado">
        <span>Servidor web: <strong><?= e($_SERVER['SERVER_SOFTWARE'] ?? 'Caddy') ?></strong>
            en el contenedor <strong><?= e(gethostname()) ?></strong></span>
        <?php if ($error === null): ?>
            <span class="ok">PostgreSQL <?= e($version) ?> en <?= e($db['host']) ?>: conectado</span>
        <?php else: ?>
            <span class="error">PostgreSQL en <?= e($db['host']) ?>: <?= e($error) ?></span>
        <?php endif; ?>
    </section>

    <?php if ($error === null): ?>
    <form method="post" class="nueva">
        <input type="hidden" name="accion" value="crear">
        <input name="autor" placeholder="Tu nombre" maxlength="50" required>
        <textarea name="texto" placeholder="Escribe una nota" maxlength="500" required></textarea>
        <button type="submit">Publicar</button>
    </form>

    <?php if (!$notas): ?>
        <p class="vacio">Todavía no hay notas.</p>
    <?php endif; ?>

    <?php foreach ($notas as $n): ?>
        <article class="nota">
            <p><?= nl2br(e($n['texto'])) ?></p>
            <footer>
                <span><?= e($n['autor']) ?> · <?= e(date('d/m/Y H:i', strtotime($n['creada']))) ?></span>
                <form method="post">
                    <input type="hidden" name="accion" value="borrar">
                    <input type="hidden" name="id" value="<?= (int) $n['id'] ?>">
                    <button type="submit" class="borrar">Borrar</button>
                </form>
            </footer>
        </article>
    <?php endforeach; ?>
    <?php endif; ?>
</main>
</body>
</html>
