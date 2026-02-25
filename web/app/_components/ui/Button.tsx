import React from "react";

type ButtonVariant = "primary" | "secondary" | "danger";

export default function Button(
  props: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }
) {
  const { variant = "secondary", className = "", ...rest } = props;
  const variantClass =
    variant === "primary" ? "qb-btn-primary" : variant === "danger" ? "qb-btn-danger" : "qb-btn-secondary";
  return <button {...rest} className={`qb-btn ${variantClass} ${className}`.trim()} />;
}
