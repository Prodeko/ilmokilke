import React from "react";
import { ButtonProps } from "antd/lib/button";
import Button from "antd-button-color";
import Link, { LinkProps } from "next/link";

const customTypeArray = [
  "success",
  "warning",
  "info",
  "dark",
  "lightdark",
  "danger",
] as const;

type ValueOf<T> = T[keyof T];
type ExtendedButtonType = {
  type?: ValueOf<Pick<ButtonProps, "type">> | typeof customTypeArray[number];
};

export const ButtonLink: React.FC<
  ExtendedButtonType & Omit<ButtonProps, "type"> & LinkProps
> = (props) => {
  const { href, as, locale, ...rest } = props;
  return (
    <Link as={as} href={href} locale={locale} passHref>
      <Button {...rest} />
    </Link>
  );
};
