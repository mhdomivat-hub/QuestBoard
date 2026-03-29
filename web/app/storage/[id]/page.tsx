import { redirect } from "next/navigation";

export default function StorageDetailRedirectPage({ params }: { params: { id: string } }) {
  redirect(`/items/${params.id}`);
}
