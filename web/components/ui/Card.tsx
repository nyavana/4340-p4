import clsx from 'clsx';
import type { HTMLAttributes } from 'react';

export function Card({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      {...rest}
      className={clsx(
        'rounded-soft bg-white border border-snow-600 shadow-soft p-6',
        className,
      )}
    />
  );
}
