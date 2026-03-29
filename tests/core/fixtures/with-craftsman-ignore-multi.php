<?php

declare(strict_types=1);

namespace App\Infrastructure\Legacy;

final class LegacyMultiAdapter
{
    private string $value = '';

    // craftsman-ignore: no-setter, PHP003
    public function setValue(string $value): void
    {
        $this->value = $value;
    }

    // craftsman-ignore: PHP003, LAYER001, PHP005
    public function setOther(string $v): void
    {
        $this->value = $v;
    }
}
