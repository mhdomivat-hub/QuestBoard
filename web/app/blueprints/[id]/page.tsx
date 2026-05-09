import { redirect } from "next/navigation";

export default function BlueprintDetailRedirectPage({ params }: { params: { id: string } }) {
  redirect(`/items/${params.id}`);
}
