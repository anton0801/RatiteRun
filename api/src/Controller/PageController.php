<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Csrf;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\View\HomePage;
use RatiteRun\Api\View\PrivacyPage;
use RatiteRun\Api\View\SupportPage;

/**
 * Публичные HTML-страницы. Живут вне версионного префикса /v1, чтобы адреса
 * были человеческими: ratiterun.online/privacy-terms и /support-form.
 */
final class PageController extends Controller
{
    /** GET / */
    public function home(Request $request): Response
    {
        return Response::html(HomePage::render($this->supportEmail()));
    }

    /** GET /privacy-terms */
    public function privacy(Request $request): Response
    {
        $lastUpdated = $this->c->presets()->content('privacy.version') ?? gmdate('Y-m-d');

        return Response::html(PrivacyPage::render($lastUpdated, $this->supportEmail()))
            ->withCache(1800);
    }

    /** GET /support-form */
    public function supportForm(Request $request): Response
    {
        return Response::html(
            SupportPage::render(Csrf::issue(), $this->supportEmail()),
        )
            // страница выдаёт CSRF-токен, поэтому кэшировать её нельзя
            ->withHeader('Cache-Control', 'no-store');
    }

    /** POST /support-form */
    public function submitSupportForm(Request $request): Response
    {
        $form = $request->form();
        $ip = $request->clientIp();

        // Значения возвращаются в форму, чтобы человек не перенабирал всё заново.
        $old = [
            'name'    => is_string($form['name'] ?? null) ? $form['name'] : '',
            'email'   => is_string($form['email'] ?? null) ? $form['email'] : '',
            'subject' => is_string($form['subject'] ?? null) ? $form['subject'] : '',
            'message' => is_string($form['message'] ?? null) ? $form['message'] : '',
        ];

        try {
            Csrf::verify($request, $form);
        } catch (ApiException $e) {
            return $this->formResponse($old, [], $e->detail());
        }

        // Ловушка: заполненное скрытое поле — почти наверняка бот.
        // Отвечаем как при успехе, чтобы не подсказывать, что его раскусили.
        if (trim((string) ($form['website'] ?? '')) !== '') {
            return Response::html(
                SupportPage::render(Csrf::issue(), $this->supportEmail(), sent: true),
            )->withHeader('Cache-Control', 'no-store');
        }

        $this->c->rateLimiter()->hit('support-form:' . ($ip ?? 'unknown'), 10, 3600);

        try {
            $this->c->support()->assertNotFlooding($ip);

            $this->c->support()->create(
                $old,
                source: 'web',
                userId: null,
                ip: $ip,
                userAgent: $request->userAgent(),
            );
        } catch (ApiException $e) {
            if ($e->status() === 422) {
                return $this->formResponse($old, $e->errors(), 'Please check the highlighted fields.');
            }
            if ($e->status() === 429) {
                return $this->formResponse(
                    $old,
                    [],
                    'You have sent several messages recently. Please wait an hour before sending another.',
                );
            }
            throw $e;
        }

        Csrf::clear();

        return Response::html(
            SupportPage::render(Csrf::issue(), $this->supportEmail(), sent: true),
        )->withHeader('Cache-Control', 'no-store');
    }

    /**
     * @param array<string,string>       $old
     * @param array<string,list<string>> $errors
     */
    private function formResponse(array $old, array $errors, ?string $message): Response
    {
        return Response::html(
            SupportPage::render(
                Csrf::issue(),
                $this->supportEmail(),
                old: $old,
                errors: $errors,
                formError: $message,
            ),
            422,
        )->withHeader('Cache-Control', 'no-store');
    }

    private function supportEmail(): string
    {
        return $this->c->presets()->content('support.email') ?? 'support@ratiterun.online';
    }
}
